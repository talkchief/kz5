# Synthetic acceptance and announcement audio

These bundled WAV files are intentionally versioned source assets, not captured
customer calls. They are generated from project-authored English text using
eSpeak NG and SoX by `scripts/generate-acdc-callback-prompts.sh`; that script
records the text, voice and conversion parameters. They use telephone-compatible
8 kHz mono PCM. The script also generates the complete queue-position prefix
“Your current position is”.

The project supplies these generated assets under its MPL-2.0 license. No
third-party neural voice weights or non-commercial speech dataset are bundled.
The speech-generation tools retain their own licenses; their executable code is
not included in these WAV files. These are synthetic recordings, not a claim of
professional/native-speaker voice quality. Replace prompts with suitably
licensed recordings when a different voice is required.

Private SIP/RTP captures and live-call recordings belong outside this directory
and must never be committed. Additional language generation is not yet part of
this checkpoint's completed acceptance.
