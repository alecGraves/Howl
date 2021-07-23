scriptPath = DirectoryName[ExpandFileName[First[$ScriptCommandLine]]];
SetDirectory[scriptPath];
<< "../Howl/HowlMidiTools.wl";

(* Function and utility definitions *)

splitTrainVal[data_, fractionTrain_] := With[{
  splitIdx = Max[IntegerPart@Round[Length[data] * fractionTrain], 1]
},
  {data[[;; splitIdx - 1]], data[[splitIdx ;;]]}
];

sampleSong[encodedSong_, len_] := With[{
  index = RandomInteger[{1, Length[encodedSong] - 1}]
},
  encodedSong[[index ;; UpTo[index + len - 1]]]
];

encToNetInput[encSong_] := <|
  "NoteData" -> encSong[[All, 1 ;; 3]],
  "Notes" -> encSong[[All, 4]]
|>;

generatorFn[encToUse_, len_] := Module[{i=1, encLen=Length[encToUse]},
  Function[
  batchInfo,
  With[{
    batchSize = batchInfo["BatchSize"]
  },
    i = Mod[i, encLen]+1;
    Table[encToNetInput[sampleSong[HowlAugmentV1[ encToUse[[ Mod[i+x, encLen]+1 ]] ], len]], {x, 1, batchSize}]
  ]]
];

(* Try to load the dataset *)
dataset = Import["dataset_music_finetune_20210718.wxf"];

If[FailureQ[dataset],
  Print["Failed to load dataset! Exiting..."];
  Exit[-1];
  ,
  (*Else*)
  Print["Dataset loaded"];
];

(* Convert data into trainable format *)

encoded = (Key["EncodedNotesV1"] /@ dataset) /. _Missing -> Nothing;


(*{encTrain, encVal} = splitTrainVal[encoded, 0.9];
Print["Training set has ", Length[encTrain], " songs."];
Print["Validation set has ", Length[encVal], " songs."];*)
encTrain = encoded;
(* Build a static encVal set to use while training. *)
valGen = generatorFn[encTrain, 500];
valdata = Map[valGen,
  Table[<|"BatchSize" -> 2|>, Length[encTrain]]
];

valset = With[{flat = Flatten[valdata]},
  <|"NoteData" -> Map[Key["NoteData"], flat],
    "Notes" -> Map[Key["Notes"], flat]
  |>
];

(* Build the network *)

validNotes = Range[HowlNoteToInt["C-1"], HowlNoteToInt["B8"]];

buildSnnBlock[nodes_] := NetChain[Flatten@(
  {
    LinearLayer[#],
    ElementwiseLayer["SELU"],
    DropoutLayer[0.01, "Method" -> "AlphaDropout"]
  }& /@ nodes)
];

buildProcessingGraph[depth_] := With[{
  linearNames=Table["Linear"<>ToString[x],{x, depth}],
  concatNames=Table["Catenate"<>ToString[x],{x, depth}]
},
  NetGraph[AssociationThread[
    Join[linearNames, concatNames],
    Join[Table[buildSnnBlock[{512, 256, 512}], depth], Table[CatenateLayer[], depth]]
  ],
    Flatten@{
      {NetPort["Input"], NetPort["Input"]->"Linear1"} -> "Catenate1",
      If[depth < 2,
        Nothing,
        (* Else *)
        Table[
        {"Catenate" <> ToString[x], "Catenate" <> ToString[x] -> "Linear" <> ToString[x + 1]}
            -> "Catenate" <> ToString[x + 1],
        {x, 1, depth-1}]]
    }
  ]];

rnn = NetGraph[
  <|
    "Stack" -> CatenateLayer[2],
    "Vectorize" -> UnitVectorLayer[],
    "LSTM" -> NetChain[{
      LongShortTermMemoryLayer[416]
    }],
    "OutputProcessing" -> NetMapOperator@buildProcessingGraph[1],
    "NoteDecoder" -> NetMapOperator@NetChain[{
      LinearLayer[Length[validNotes]],
      SoftmaxLayer[]
    }],
    "NoteDataDecoder" -> NetMapOperator@NetChain[{
      LinearLayer[3],
      ElementwiseLayer[LogisticSigmoid],
      ElementwiseLayer[#*3&]
      }]
  |>,
  {
    {NetPort["NoteData"], NetPort["Notes"] -> "Vectorize"}
      -> "Stack"
      -> "LSTM"
      -> "OutputProcessing"
      -> {
        "NoteDecoder" -> NetPort["NotePred"],
        "NoteDataDecoder" -> NetPort["NoteDataPred"]
      }
  },
  "Notes" -> {"Varying", NetEncoder[{"Class", validNotes}]},
  "NoteData" -> {"Varying", 3}
  (*"NotePred" -> NetDecoder[{"Class",validNotes}]*)
];

trnn = NetGraph[
  <|
    "rnn" -> rnn,
    "restNote" -> SequenceRestLayer[],
    "mostNote" -> SequenceMostLayer[],
    "restNoteData" -> SequenceRestLayer[],
    "mostNoteData" -> SequenceMostLayer[],
    "meanSquaredLoss" -> MeanSquaredLossLayer[],
    "categoricalLoss" ->  CrossEntropyLossLayer["Index"],
    "lossTotal" -> TotalLayer[]
  |>,
  {
    NetPort["Notes"] -> {"mostNote", "restNote"} ,
    NetPort["NoteData"] -> {"mostNoteData", "restNoteData"},
    {"mostNoteData", "mostNote"} -> "rnn",
    {NetPort["rnn", "NoteDataPred"], "restNoteData"}
        -> "meanSquaredLoss"
        -> "lossTotal",
    NetPort["rnn", "NotePred"] -> NetPort["categoricalLoss", "Input"],
    "restNote" -> NetPort["categoricalLoss", "Target"],
    "categoricalLoss" -> "lossTotal" -> NetPort["Loss"]
  },
  "Notes" -> {"Varying", NetEncoder[{"Class", validNotes}]},
  "NoteData" -> {"Varying", 3}
];

(* save the training network *)

If[FailureQ[trnn],
  Print["Building network failed. Exiting..."];
  Exit[-1]];

Print[Information[trnn]];
dateTimeStr = StringReplace[DateString["ISODateTime"], ":"->"-"];
If[FailureQ[checkpointDir = CreateDirectory[FileNameJoin[{scriptPath, "checkpoints_"<>dateTimeStr}]]],
  Print["creating checkpoint directory failed. Exiting..."]; Exit[-1]];
trainSaveName = Export[FileNameJoin[{checkpointDir, "training_start" <> dateTimeStr <> ".wlnet"}], trnn];
Print["Training net saved: ", trainSaveName];

(* Train the network *)

Print["Starting Training..."];

trainingResults = NetTrain[
  trnn,
  {
    generatorFn[encTrain, 500],
    (* # of rounds, each batch is one song, so we set rounds to (# of batches) * songs. *)
    "RoundLength" -> Length[encTrain] * 4 * 4
  },
  All,
  ValidationSet -> valset,
  LossFunction -> "Loss",
  BatchSize-> 24,
  TrainingProgressCheckpointing-> {
    "Directory", checkpointDir, "Interval"->Quantity[2,"Hours"]
  },
  TargetDevice -> {"GPU", 1},
  WorkingPrecision -> "Mixed",
  TimeGoal -> Quantity[12, "Hours"]
];


If[FailureQ[trainingResults],
  Print["Training failed. Exiting..."];
  Exit[-1]];

Print["Training Complete!"];

trained = trainingResults["TrainedNet"];
predictor = NetGraph[<|
  "rnn" -> NetExtract[ trained, "rnn"],
  "lastPred" -> SequenceLastLayer[],
  "lastDataPred" -> SequenceLastLayer[]
|>,
  {
    NetPort["rnn", "NotePred"] -> "lastPred" -> NetPort["NotesPred"],
    NetPort["rnn", "NoteDataPred"] ->
        "lastDataPred" -> NetPort["NoteDataPred"]
  },
  "Notes" -> {"Varying", NetEncoder[{"Class", validNotes}] },
  "NotesPred" -> NetDecoder[{"Class", validNotes}]
];

predSaveName = Export[FileNameJoin[{checkpointDir, "predictor_"<>dateTimeStr<>".wlnet"}], predictor];
Print["Predictor saved: ", predSaveName];

resSaveName = Export[FileNameJoin@{checkpointDir,"results_"<>dateTimeStr<>".wxf"}, trainingResults];
Print["Results saved: ", resSaveName];




