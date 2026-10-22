# ELEGANCE BARBER · Reservas (Android)

This Android app opens the existing production reservations page at:
https://elegance-barber-piste.vercel.app/cliente

It uses the live website and its existing Supabase connection; it does not bundle Supabase credentials or create a separate database.

## Build
GitHub Actions workflow **Build Android Reservations APK** builds a debug-signed APK and uploads it as an artifact. Download the APK from the successful workflow run, then share it with Android customers. Android may show a warning because this is distributed outside Google Play.

## Notes
- Requires internet access to make and manage reservations.
- This first icon is a black-and-gold E monogram, not a verified copy of the original uploaded logo.
- iPhone users must install the website from Safari; Android APKs cannot be installed on iOS.
