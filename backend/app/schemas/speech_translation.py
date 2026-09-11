"""Speech-to-speech translation contract.

The classroom records a sentence in the teaching medium (Hindi), the device
uploads that audio, and the backend proxies it to the public Adi Vaani ISTS
endpoint which answers with a transcript, the mother-tongue (Santali)
translated text, and a WAV payload carrying the spoken translation.

The device trusts exactly these fields. `audio` on the wire is a base64
payload whose exact encoding is passed through verbatim from Adi Vaani — the
proxy never decodes or re-encodes it, so the device and the source agree on
whatever format the provider actually produced.
"""

from __future__ import annotations

from app.schemas.common import APIModel


class SpeechTranslateResponse(APIModel):
    """What the device needs from one Hindi-audio -> Santali-audio turn.

    ``transcript`` is what Adi Vaani heard in the source language,
    ``translatedText`` is the Santali sentence it produced, and ``audio`` is
    the provider's own spoken-translation payload (base64 WAV), passed through
    untouched. ``provider`` is always ``adivaani`` so the device can label the
    answer honestly and never invent provenance.
    """

    transcript: str
    translated_text: str
    audio: str
    content_type: str = "audio/wav"
    provider: str = "adivaani"