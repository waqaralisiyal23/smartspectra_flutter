# smartspectra_flutter example: Live Vitals

A one-screen demo of the [`smartspectra_flutter`](../) plugin. It shows the
front camera with live readings:

- Pulse rate and breathing rate
- HRV (RMSSD) after 60 seconds
- Dominant facial expression
- Blink count

For wellness and informational use only. Not a medical device.

## Run it

You need a physical Android (API 28+) or iOS (17+) device, and a free API key
from the [Presage developer portal](https://physiology.presagetech.com/auth/register).

```sh
./setup.sh                               # generates android/ and ios/ (macOS)
cp api_keys.example.json api_keys.json   # then paste your API key
flutter run --dart-define-from-file=api_keys.json
```

`api_keys.json` is git-ignored, so your key stays out of the repository.

## Tips

- Hold the phone steady in even light, with your face filling the frame.
- Breathing needs the phone propped up, and you not talking.
- If starting fails with `Could not resolve host`, your network's DNS can't
  reach Presage. Set a public DNS on the phone (Android: Private DNS
  `one.one.one.one`).
