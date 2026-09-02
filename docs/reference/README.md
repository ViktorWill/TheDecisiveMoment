# Reference implementation

`vectors.py` is a throwaway Python implementation of the model in
[../EXPOSURE-MODEL.md](../EXPOSURE-MODEL.md). It is **not** part of the app and nothing depends on
it.

It exists for one reason: every numeric test vector in `EXPOSURE-MODEL.md` was produced by running
it. If you change the model, run this first, check the independent cross-checks still hold, and then
update both the document and the Swift tests from its output.

```sh
python3 docs/reference/vectors.py
```

The cross-checks worth watching, because they are the ones that catch a wrong model rather than a
wrong transcription:

- NYC winter-solstice noon elevation must equal `90 − 40.7308 − 23.438 = 25.83°`.
- f/16 at 1/100 and ISO 100 must give EV100 14.64 — the true value behind "Sunny 16".
- The front-lit-subject column must stay between roughly EV 14.6 and 15.3 for sun elevations from 5°
  to 90°. That flatness *is* Sunny 16, and the model derives it rather than being fitted to it.

If a change breaks that third one, the change is wrong.
