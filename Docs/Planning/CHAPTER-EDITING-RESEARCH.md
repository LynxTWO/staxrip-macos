# Chapter editing discovery

Date: 2026-10-01. Planning evidence for Slice 030, not implementation acceptance.

FFmpeg documents a UTF-8 metadata file with chapter sections, rational time bases and escaped special characters. This provides an argument-only planning path followed by a generated metadata file inside owned staging. Reference: https://ffmpeg.org/ffmpeg-formats.html#Metadata.

Generated six-second 160 by 96 H.264 media and three authored ranges (0-2, 2-4, 4-6 seconds) produced matching titles in MKV and MP4, including Unicode and escaped equals, hash, semicolon and backslash characters. A 1-5 second trim produced 0-1, 1-3 and 3-4 second chapters in both containers.

A gap list at 1-2 and 3-4 seconds survived MKV. MP4 rewrote it to 0-3 and 3-4, supporting the existing admission rule requiring a zero-start contiguous MP4 chapter list. Do not rely on successful encoding as chapter preservation evidence.

An exact 2-4 trim retained zero-length boundary chapters at 0-0 and 2-2 in both containers. The custom planner must exclude entries with no strictly positive intersection before generating metadata. Runtime output verification must still refuse invalid or changed chapter ranges.

A microsecond metadata time base and trim from 1.125123 for 3.250234 seconds produced MKV chapter boundaries at 0, 0.874877, 2.874877 and 3.250234. MP4 represented these at millisecond precision (0, 0.875, 2.875, 3.250). Author times in integer milliseconds; retain microsecond trim offsets in generated metadata and verify against each supported output time base. Reject unsupported precision or nonpositive representable output intervals.

Ignored chapter-discovery files retain command-generated fixtures and probe JSON. These experiments establish only the listed short fixtures and installed FFmpeg, not all metadata, source origins or player behavior. Default source preservation, attachments, source bytes and audio remain unchanged by this research.
