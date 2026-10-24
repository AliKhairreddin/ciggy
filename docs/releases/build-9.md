# TestFlight 1.0 (9) — What to Test

Motion calibration now saves on Watch and sends an hourly batch through the normal background file transfer, with at most two raw files in transfer at once. The immediate multipart sender has been removed. Live motion buffers stay continuous across ordinary history checks instead of flushing each minute. Existing pairing and sharing choices are kept.

Cigarette detection, grouping, counters and event sync are unchanged by this build. Only optional calibration delivery is batched. The iPhone uploads received files over Wi-Fi.

Update both iPhone and Watch apps. Check that the Watch opens repeatedly without closing unexpectedly, your cigarette counter works as before, and saved motion eventually uploads while your paired iPhone has Wi-Fi. In Settings → Private motion calibration, the queue can wait for an hourly batch. Retry checks status and retries phone uploads; it does not force immediate Watch motion delivery.

The dashboard at https://ciggy.thatcanadian.dev now automatically graphs all received recordings together, without selecting or comparing individual files. It shows measured movement ranges, gaps, recorded time and latest-motion/upload times. Hover for time and measured values. Advanced date/source controls remain available. Labels do not change your count or train a model automatically.

watchOS controls actual wake and transfer timing, so delivery can take longer than an hour. The Watch queue retains up to 80 MB or 48 hours, whichever limit is reached first. Shared recordings and labels expire after 14 days. Only motion after your consent is shared. The reported physical Watch crash could not yet be confirmed from its crash report; this build reduces calibration transfer and extraction pressure, but please report if closing unexpectedly continues.
