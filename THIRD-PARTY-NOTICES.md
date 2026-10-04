# Third-party notices

Streaming loudness meter K-weighting, integrated-gate design and true-peak filter adapted from SignalForge, revision 93d82e2796ac4c148033fc45dc067af1746b3b29, crates/signalforge-analysis/src/lib.rs. The adaptation uses Double precision and adds local report/streaming integration.

MIT License

Copyright (c) 2026 Daniel Boyd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


The bundled read-only staxrip-dolby-metadata-audit helper uses MIT libdovi 3.3.2
from quietvoid/dovi_tool, pinned to revision
82384bc7652c6f88cb63f7f11e0315b624003fc3. Cargo.lock pins its transitive dependencies.
Their complete supplied license texts and package/hash inventory are included in
Contents/Resources/DolbyMetadataLicenses in the development app; source copies are
under Tools/DolbyMetadataAudit/LICENSES and DEPENDENCY-LICENSES.json. The helper's
own MIT license is included there as LICENSE-staxrip-helper. No GPL enhancement
reconstruction code is bundled. Runtime FFmpeg/FFprobe remains a separately
installed tool, subject to the license of the user's particular build.

The helper also links the Rust standard library. The active build toolchain's
supplied library attribution catalog, license texts, compiler version and content
hash inventory are included in DolbyMetadataLicenses/RustLibrary. That catalog
can mention toolchain components beyond the linked runtime; it is not a claim
that every listed component or license applies to this executable.
