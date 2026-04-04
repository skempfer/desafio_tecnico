%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: ["_build/", "deps/"]
      },
      requires: [],
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Readability.MaxLineLength, max_length: 100},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Consistency.LineEndings},
        {Credo.Check.Refactor.CyclomaticComplexity},
        {Credo.Check.Readability.ModuleDoc}
      ]
    }
  ]
}
