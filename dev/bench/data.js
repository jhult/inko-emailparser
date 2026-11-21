window.BENCHMARK_DATA = {
  "lastUpdate": 1795233081441,
  "repoUrl": "https://github.com/jhult/inko-emailparser",
  "entries": {
    "Benchmark": [
      {
        "commit": {
          "author": {
            "email": "Jonathan@JonathanHult.com",
            "name": "Jonathan Hult",
            "username": "jhult"
          },
          "committer": {
            "email": "Jonathan@JonathanHult.com",
            "name": "Jonathan Hult",
            "username": "jhult"
          },
          "distinct": true,
          "id": "5c84258d5afb6a0fd23afbf10ad29606109f7353",
          "message": "ci: create benchmark data branch when missing\n\ngithub-action-benchmark fetches its history branch instead of creating it, so the benchmark job failed on every trunk push with \"couldn't find remote ref benchmark-data\". Seed an empty orphan commit before the action runs, gated to trunk pushes and idempotent once the branch exists.",
          "timestamp": "2026-11-20T21:49:51-06:00",
          "tree_id": "20070adfddcbd315f4d55ae5d2bf58a5c0450376",
          "url": "https://github.com/jhult/inko-emailparser/commit/5c84258d5afb6a0fd23afbf10ad29606109f7353"
        },
        "date": 1795233081233,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "simple_email_1000",
            "value": 12,
            "unit": "ms"
          },
          {
            "name": "multipart_500",
            "value": 16,
            "unit": "ms"
          },
          {
            "name": "base64_1000",
            "value": 22,
            "unit": "ms"
          },
          {
            "name": "quoted_printable_1000",
            "value": 22,
            "unit": "ms"
          },
          {
            "name": "header_parsing_10000",
            "value": 31,
            "unit": "ms"
          },
          {
            "name": "address_parsing_5000",
            "value": 19,
            "unit": "ms"
          }
        ]
      }
    ]
  }
}