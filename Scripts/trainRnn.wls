(* Mathematica Script *)
(* :Author: Alec Graves *)
(* :Date: 2021-07-20 *)

(* :Mathematica Version: 12.3 *)
(* :Copyright: (c) 2021 Alec Graves *)
(* THE UNLICENSE *)

(* Import Howl library midi tools *)
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
  "NoteData" -> NumericArray[encSong[[All, 1 ;; 3]], "Real32"],
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

(* Use the same data for training and validation *)
encTrain = encoded;
encVal = encoded;


(* Build a static encVal set to use while training. *)
valGen = generatorFn[encVal, 500];
valdata = Map[valGen,
  Table[<|"BatchSize" -> 2|>, Length[encVal]]
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
    Join[Table[buildSnnBlock[{256, 256, 256}], depth], Table[CatenateLayer[], depth]]
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
      LongShortTermMemoryLayer[192]
    }],
    "OutputProcessing" -> NetMapOperator@buildProcessingGraph[1],
    "NoteDecoder" -> NetMapOperator@NetChain[{
      LinearLayer[Length[validNotes]],
      SoftmaxLayer[]
    }],
    "NoteDataDecoder" -> NetMapOperator@NetChain[{
      LinearLayer[3],
      ElementwiseLayer[LogisticSigmoid],
      ElementwiseLayer[#*4&]
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

(* Build the training network with loss functions included: *)

trnn = NetGraph[
  <|
    "rnn" -> rnn,
    "restNote" -> SequenceRestLayer[],
    "mostNote" -> SequenceMostLayer[],
    "restNoteData" -> SequenceRestLayer[],
    "mostNoteData" -> SequenceMostLayer[],
    "meanSquaredLoss" -> MeanSquaredLossLayer[],
    "x3" -> ElementwiseLayer[#*3&],
    "categoricalLoss" ->  CrossEntropyLossLayer["Index"],
    "lossTotal" -> TotalLayer[]
  |>,
  {
    NetPort["Notes"] -> {"mostNote", "restNote"} ,
    NetPort["NoteData"] -> {"mostNoteData", "restNoteData"},
    {"mostNoteData", "mostNote"} -> "rnn",
    {NetPort["rnn", "NoteDataPred"], "restNoteData"}
        -> "meanSquaredLoss" -> "x3"
        -> "lossTotal",
    NetPort["rnn", "NotePred"] -> NetPort["categoricalLoss", "Input"],
    "restNote" -> NetPort["categoricalLoss", "Target"],
    "categoricalLoss" -> "lossTotal" -> NetPort["Loss"]
  },
  "Notes" -> {"Varying", NetEncoder[{"Class", validNotes}]},
  "NoteData" -> {"Varying", 3}
];


If[FailureQ[trnn],
  Print["Building network failed. Exiting..."];
  Exit[-1]];

(* Make a checkpoint directory and save the training net (uninitialized) *)


Print[Information[trnn]];
dateTimeStr = StringReplace[DateString["ISODateTime"], ":"->"-"];
If[FailureQ[checkpointDir = CreateDirectory[FileNameJoin[{scriptPath, "checkpoints_"<>dateTimeStr}]]],
  Print["creating checkpoint directory failed. Exiting..."]; Exit[-1]];
trainSaveName = Export[FileNameJoin[{checkpointDir, "training_start" <> dateTimeStr <> ".wlnet"}], trnn];
Print["Training net saved: ", trainSaveName];

(* Train the network *)


Print["Generating training dataset"];

(* Configurable batch parameters. *)
(* outOfCore generates batches of augmented data on the fly, but will be 3x slower during training. *)
outOfCore = True;
(* exampleLength is the length of our note sequence to train on. *)
exampleLength = 768;

trainSet = With[{trainDataGen = generatorFn[encTrain, exampleLength]},
    If[outOfCore,
      {trainDataGen, "RoundLength"->Length[encTrain]*4}
    , (* Else *)
      (* Cache large number of training batches *)
      Block[{
        examplePerSong = 490,
        trainData
      },
      trainData = Flatten[Table[
        Print[i, " of ", examplePerSong]; trainDataGen[<|"BatchSize"->Length[encTrain]|>],
        {i, examplePerSong}
      ]];
      With[{flat = Flatten[trainData]},
        <|
          "NoteData" -> Map[Key["NoteData"], flat],
          "Notes" -> Map[Key["Notes"], flat]
        |>
      ]]]];

Print["Starting Training..."];

trainingResults = NetTrain[
  trnn,
  trainSet,
  All,
  ValidationSet -> valset,
  LossFunction -> "Loss",
  TrainingProgressCheckpointing-> {
    "Directory", checkpointDir, "Interval"->Quantity[2,"Hours"]
  },
  TargetDevice -> {"GPU", 1},
  BatchSize -> 64,
  WorkingPrecision -> "Mixed",
  TimeGoal -> Quantity[10, "Hours"]
];


If[FailureQ[trainingResults],
  Print["Training failed. Exiting..."];
  Exit[-1]];

Print["Training Complete!"];

(* Save the training output files (training results data and final model) *)

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
