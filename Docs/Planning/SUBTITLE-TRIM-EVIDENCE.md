# Trimmed external caption evidence

Slice 036 under D-064 / R-045 is implemented and awaiting final native/regression acceptance.

The old no-trim unit assertion failed after the explicitly approved capability change. It was replaced with a positive clipped-timeline assertion; known-zero-start, duration, HDR, malformed, byte and cue bounds remain enforced. New independent cases cover both crossing boundaries, adjacency, outside-only intervals, Unicode byte retention, full containment, invalid precision and open end. No-cue selection is an actionable refusal, not an omitted track.

Focused validation passed 14 tests / 3 suites in 0.670 seconds. Actual generated VFR exports in MKV/AAC, MP4/AAC and MKV/Opus preserve the intended three decoded caption ranges and every selected decoded video timestamp within the declared mux tick. Custom chapters decode at [0,1.5) and [1.5,3), with literal titles. A source audio track delayed to three seconds retains its one-second delay after the two-second trim; independent timestamp-aware PCM decoding checks the silent prefix, tone onset and sustained energy. The 25 ms onset bound covers one AAC frame plus rounding; this is a generated timing check, not listening or long-film synchronization acceptance.

The complete caption integration subset passed 9 tests / 2 suites in 5.306 seconds. Added trimmed cases prove that a one-millisecond altered staged cue cannot publish and that changing the original SRT after capture affects only the next attempt. Existing untrimmed tests retain their original expectations. Source/caption bytes, unrelated staging and competing output protections remain checked.

The plan owns the transformed document and BatchController writes that snapshot. Runtime cue extraction compares against the same immutable expected document. Only the external-caption-plus-trim combination uses trim/setpts and atrim/asetpts in place of global output seek. Custom chapter metadata explicitly uses output time for this combination; all existing callers keep source-time metadata by default. No session fields, source-access ownership or publication policy changed.

Native correction/export, optimized build receipt, full local/hosted regression and final audit remain pending. Real-film, arbitrary discontinuities, other encoders/hardware and owner listening remain outside current evidence.
