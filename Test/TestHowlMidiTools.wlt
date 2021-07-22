(* Mathematica Test File *)
(* Created by the Wolfram Language Plugin for IntelliJ, see http://wlplugin.halirutan.de/ *)

scriptPath = DirectoryName[ExpandFileName[First[$ScriptCommandLine]]];
ret = Get["Howl/HowlMidiTools.wl", Path -> FileNameJoin[{scriptPath, ".."}]];

BeginTestSection["TestNoteConversion"]

VerificationTest[(* 1 *)
  {HowlNoteToInt["c4"], HowlNoteToInt["C4"]}
  ,
  {0, 0}
];

VerificationTest[(* 2 *)
  HowlNoteToInt[1.0]
  ,
  1
];

VerificationTest[(* 3 *)
  HowlNoteToInt /@ {"C4", "C5", "C3"}
  ,
  {0, 12, -12}
];

VerificationTest[(* 4 *)
  HowlNoteToInt /@ {"C#4", "C#5", "C#3"}
  ,
  (HowlNoteToInt /@ {"C4", "C5", "C3"}) + 1
];

VerificationTest[(* 5 *)
  HowlIntToNote /@ {0, 12, -12}
  ,
  {"C4", "C5", "C3"}
];

(*Enforce min/max notes*)
VerificationTest[(* 6 *)
  {HowlIntToNote[HowlNoteToInt["B4"] + 12*100],HowlIntToNote[HowlNoteToInt["C-1"] -12*100]}
  ,
  {"B8", "C-1"}
];

(* loading a midi *)
VerificationTest[(* 7 *)
  With[{ testfile = FileNameJoin[{scriptPath, "test.mid"}] },
    If[!FileExistsQ[testfile], Export[testfile, Sound@{SoundNote /@ {"C", "B5", "F#-1"}}]];
    HowlMidiImport[testfile]["Notes"] /. SoundNote[x_, __] :> x
  ]
  ,
  {"C4", "B5", "F#-1"}
];

(* loading nonexistent midi $Failed *)
VerificationTest[(* 8 *)
  With[{testfile=FileNameJoin[{scriptPath, "nonexistent.mid"}]},
    HowlMidiImport[testfile]["Notes"]
  ]
  ,
  $Failed
];

VerificationTest[(* 9 *)
  HowlEncodeNotesV1[Apply[SoundNote] /@ {{"C4", {0, 1}, "Violin", SoundVolume -> 0.3},
    {"B5", {1, 2}, "Viola"},
    {"F#-1", {3, 4}}
  }]
  ,
  {{0, 1, 0.3, 0}, {1, 1, 1.0, 23}, {2, 1, 1.0, -54}}
];

With[{notes = Apply[SoundNote] /@ {
  {"C4", {0, 1}, SoundVolume -> 0.1},
  {"B5", {1, 2}, SoundVolume -> 0.2},
  {"F#-1", {3, 4}, SoundVolume -> 0.3}
}},
  VerificationTest[(* 10 *)
    HowlDecodeNotesV1[HowlEncodeNotesV1[notes]]
    ,
    notes
  ];
];

VerificationTest[(* 11 *)
  HowlAugmentV1@HowlEncodeNotesV1[Apply[SoundNote] /@ {{"C4", {0, 1}, "Violin", SoundVolume -> 0.3},
    {"B5", {1, 2}, "Viola"},
    {"F#-1", {3, 4}}
  }] // First // Length
  ,
  4
];


EndTestSection[]


