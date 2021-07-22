#!/usr/bin/env wolframscript

(* Wolfram Script *)
(* Created by the Wolfram Language Plugin for IntelliJ, see http://wlplugin.halirutan.de/ *)
(* :Author: Alec *)
(* :Date: 2021-07-17 *)

Print["Running Tests"];

scriptPath = DirectoryName[ExpandFileName[First[$ScriptCommandLine]]];
testFiles =  FileNames[FileNameJoin[{scriptPath, "*.wlt"}]];


str[x_] := TextString[x];


printFailedTest[rs_] := If[rs["Outcome"] == "Failure",
  Print[
    "    " <> "test" <> str@rs["TestIndex"]
        <> " Expected: " <> str@rs["ExpectedOutput"] <> " | Actual: " <> str@rs["ActualOutput"]
  ]
];

printReport[report_] := With[{r=report /. TestReportObject[x_] :> x},
  With[{failed = r["TestsFailedCount"] != 0},
    If[failed, Print[]];
    Print[r["Title"] <>" ... "<>If[failed, "Failed ❌", "Passed ✔"]];
    If[failed,
      Print["    "<>"Count Failed: "<>str@r["TestsFailedCount"]];
      Map[printFailedTest, (r["TestResults"] /. TestResultObject[x_] :> x)];
      Print[];
    ];
  ]
];

Map[Composition[printReport, TestReport], testFiles];

Print[];

