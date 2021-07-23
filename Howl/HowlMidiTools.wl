(* Mathematica Package *)
(* Created by the Wolfram Language Plugin for IntelliJ, see http://wlplugin.halirutan.de/ *)

(* :Title: HowlMidiTools *)
(* :Context: HowlMidiTools` *)
(* :Author: Alec Graves *)
(* :Date: 2021-07-17 *)

(* :Package Version: 0.1 *)
(* :Mathematica Version: 12.3 *)
(* :Copyright: (c) 2021 Alec Graves *)
(* :Keywords: *)
(* :Discussion: *)

(* This package contains procedures useful in dealing with MIDI files. *)

BeginPackage["HowlMidiTools`"];
(* Exported symbols added here with SymbolName::usage *)

HowlNoteToInt::usage = "HowlNoteToInt[note_String] converts a note (e.g. \"c#2\")
into integer semitones from middle C (C4)";

HowlIntToNote::usage = "HowlIntToNote[note_Integer] converts an Integer number of semitones from C4
(e.g. 1) to a note string (e.g. \"C#4\")";

HowlFindMidis::usage = "HowlFindMidis[directory_String] returns a list of all midi FileNames in that directory";

HowlMidiImport::usage = "HowlMidiImport[file_String] imports a midi file, saving flat list of SoundNotes in all tracks.
returns an association <|\"File\" -> String path, \"Notes\" -> notes, \"EncodedNotesV1\" -> encode[notes]|>.
\n
OriginalNotes and EncodedData will be $Failed on import failures, so be sure to filter these out:
\n
noFailures = Query[Select[ !FailureQ[#[\"Notes\"]]& ]][myImportedData]";

HowlEncodeNotesV1::usage = "Encodes a list of SoundNote[note, {start, end}, volume] into
{timeSinceLastNote, duration, volume, noteInteger}. Note there is no instrument information preserved.";

HowlDecodeNotesV1::usage = "Converts {timeSinceLastNote, duration, volume, noteInteger} into SoundNotes.
Note there is no instrument information preserved. ";

HowlAugmentV1::usage = "Applies random speed warp and pitch shift to notes from HowlEncodeNotesV1";

Begin["`Private`"];


Clear[octThresh];
octThresh[oct_] := Clip[oct, {-1, 8}];

Clear[intToOctSemi];
(* Convert integer to {octave, semitone} tuple AND apply octave threshold *)
intToOctSemi[x_] := {octThresh[Floor[x / 12 + 4]], Mod[x, 12]};

Clear[octSemiToInt];
(* Convert octave and semitone args to Integer note rep. AND apply octave threshold *)
octSemiToInt[octave_, semitone_] := (octThresh[octave] - 4) * 12 + semitone;
(* Vectorized version: *)
octSemiToInt[octSemi_] := (octThresh[octSemi[[1]]] - 4) * 12 + octSemi[[2]];

ClearAll[keyToNum, numToKey];
(* Convert our notes to integer semitone representation *)
keyToNum = <|"C" -> 0, "C#" -> 1, "Db" -> 1, "D" -> 2, "D#" -> 3,
  "Eb" -> 3, "E" -> 4, "F" -> 5, "F#" -> 6, "Gb" -> 6, "G" -> 7,
  "G#" -> 8, "Ab" -> 8, "A" -> 9, "A#" -> 10, "Bb" -> 10, "B" -> 11 |>;
numToKey = With[{
  (* remove flats, so inverted association defaults to sharps. *)
  noflat=KeyDrop[keyToNum, Select[Keys[keyToNum], StringContainsQ["b"] ]]
},
  (*GeneralUtils`AssociationInvert*)
  AssociationThread[Values[noflat], Keys[noflat]]
];

Clear[HowlNoteToInt];
HowlNoteToInt[note_String] := With[{
  numChars = StringCases[note, {"-", DigitCharacter}]
},
  With[{
    octave = If[Length[numChars] == 0,
      4,
      numChars // StringJoin // Interpreter["Integer"] /. _?FailureQ -> 4],
    semitones = keyToNum[StringDelete[note, numChars] // ToUpperCase] /. _Missing -> 0
  },
    octSemiToInt[octave, semitones]
  ]
];

(* If we pass an Integer or Real, we want to apply octave thresholding, so run it through octSemiToInt. *)
HowlNoteToInt[x:(_Real | _Integer)] := octSemiToInt[intToOctSemi[IntegerPart@Round[x]]];

Clear[HowlIntToNote];
HowlIntToNote[note_Integer] := With[{
    octaveSemitone = intToOctSemi[IntegerPart@Round[note]]
  },
  numToKey @ octaveSemitone[[2]]  <> ToString @ octaveSemitone[[1]]
];

Clear[noteSort];
(*Sort a list of SoundNotes.*)
noteSort[notes_] :=
    SortBy[notes, {
      (* Sort by note start time (round to nearest hundredth for smoothness) *)
      Round[First[Replace[#, SoundNote[_, x_, __] :> x]], 0.01] &,
      (* Tie breaker of note height *)
      HowlNoteToInt[Replace[#, SoundNote[x_, __] :> x]] &
    }];

Clear[safeMidiImport];
(* Avoids midi import bugs in Mathematica *)
(* https://mathematica.stackexchange.com/questions/251024/how-to-get-correct-note-timings-when-importing-multi-track-midi-files *)
safeMidiImport[file_String] :=
    With[{nTracks = Quiet@Import[file, {"MIDI", "TrackCount"}]},
      If[FailureQ[nTracks /. { ("TrackCount" /. $Failed) -> $Failed }],
        $Failed
        ,  (* Else, no import failure, continue. *)
        noteSort@Flatten[Map[Import[file, {"SoundNotes", #}] &, Range[nTracks]]]]
    ];

(**********************************)
(* Data Encoding                  *)
(**********************************)

Clear[extractRaw];
(* get note in form {start, duration, volume, pitch} *)
extractRaw[notes_] := notes /. {
  SoundNote[pitch_, times_, ___, SoundVolume -> volume_]
      :> {times[[1]], Abs[times[[2]] - times[[1]]], volume, HowlNoteToInt[pitch]},
  (* Set volume to 1 if not included: *)
  SoundNote[pitch_, times_, ___] :> {times[[1]], Abs[times[[2]] - times[[1]]], 1.0, HowlNoteToInt[pitch]},
  SoundNote[___] -> Nothing
};


Clear[startTimesToDelays];
(* Convert start times to delay since previous note *)
startTimesToDelays[raw_] :=
    Join[{raw[[1]]*{0, 1, 1 , 1 }}, With[{rt = Transpose[raw]},
      Transpose[
        Join[{rt[[1, 2 ;;]] - rt[[1, 1 ;; -2]]}, rt[[2 ;;, 2 ;;]]]]]];

Clear[HowlEncodeNotesV1];
HowlEncodeNotesV1[notes_] := notes // extractRaw // startTimesToDelays;

Clear[rawToNote];
rawToNote[raw_] := raw /. {
  {start_, duration_, volume_, pitch_} :>
      SoundNote[HowlIntToNote[pitch], {start, start + duration},
        SoundVolume -> volume]
};

Clear[delaysToStartTimes];
(* Convert delay between notes to start times for each note *)
delaysToStartTimes[encoded_] :=
    With[{et = Transpose[encoded]},
      Transpose[Join[{Accumulate[et[[1]]]}, et[[2 ;;]], 1]]];

Clear[HowlDecodeNotesV1];
HowlDecodeNotesV1[encoded_] := encoded // delaysToStartTimes // rawToNote;

(**********************************)
(* Data Augmentation              *)
(**********************************)

Clear[timeWarp];
(* Now, look how easy it is to add time effects when we choose a good \
format *)
timeWarp[encoded_, warpFactor_] :=
    Transpose[Transpose[encoded] * {warpFactor, warpFactor, 1, 1}];

Clear[pitchShift];
pitchShift[encoded_, semitones_] := With[{et = Transpose[encoded]},
  (* Perform octave/semitone conversion and back to enforce min and max notes. *)
  Transpose @ Join[et[[;;-2]], {octSemiToInt[intToOctSemi[et[[-1]] + semitones]]}]
];

Clear[volumeShift];
volumeShift[encoded_, volShift_] := With[{et = Transpose[encoded]},
  (* Perform octave/semitone conversion and back to enforce min and max notes. *)
  Transpose @ Join[et[[;;2]], {et[[3]]*volShift}, {et[[-1]]}]
];

Clear[HowlAugmentV1];
HowlAugmentV1[encodedV1_] := encodedV1 // Composition[
  timeWarp[#, RandomReal[{0.5, 2.0}]]&,
  pitchShift[#, RandomInteger[{-11, 11}]]&,
  volumeShift[#, RandomReal[{0.8, 1.0}]]&
];


(*******************)
(* Dataset Loading *)
(*******************)

(* Note, this takes 2 minutes with a directory containing 200,000 files. *)
Clear[HowlFindMidis];
HowlFindMidis[directory_String] := FileNames["*.mid", directory, Infinity, IgnoreCase -> True];


Clear[HowlMidiImport];
(* Note, this takes around 3 seconds per midi file. *)
HowlMidiImport[midi_] := With[{notes = Quiet[safeMidiImport[midi]]},
  If[FailureQ[notes] || Length[notes] < 2,
    <|"File" -> midi, "Notes" -> $Failed|>
    ,
    <|"File" -> midi, "Notes" -> notes, "EncodedNotesV1" -> HowlEncodeNotesV1[notes]|>
  ]
];

End[]; (* `Private` *)

EndPackage[]