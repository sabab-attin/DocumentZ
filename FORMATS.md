# Reader format support

The file picker, stored library metadata, reader routing, and sharing recognize every extension in the supplied format overview. Recognition is separate from rendering fidelity and PDF standards certification.

| Formats | Reading on Android, Windows and web | Windows conversion |
| --- | --- | --- |
| PDF; PDF/A, PDF/X, PDF/E, PDF/UA files | Existing PDF reader renders supported 2D page content, text, images and links. | No conversion needed. |
| EPUB | Reflowable single pages, two-page spreads or continuous reading; embedded images, search, chapter and footnote links, contents and text marks. | No conversion needed. |
| DOCX | Text, basic bold/italic/underline/strike, tables and embedded raster images. | LibreOffice supplies a PDF page layout. |
| XLSX | Named sheets, sparse cell positions, shared/inline strings, cached values and formula text where cached results are absent. | LibreOffice supplies a printable PDF. |
| PPTX | Slide order, text and embedded raster images in a reading view. | LibreOffice supplies a PDF slide layout. |
| ODT, ODS, ODP | Paragraphs/headings, sheet tables, slide sections and embedded raster images. | LibreOffice supplies a PDF layout. |
| TXT, Markdown | Escaped text; UTF-8/UTF-16 text; Markdown headings, lists, tables, emphasis and code. | Not required. |
| RTF | Readable text, Unicode, escaped characters and paragraph breaks. | LibreOffice supplies formatted PDF layout. |
| HTML, HTM | Local HTML reading view, selectable paragraphs and embedded data images. | Not required for the reading view. |
| MHTML, MHT | Multipart saved-page HTML and bundled raster images; base64/quoted-printable resources. | Not required for the reading view. |
| PNG, JPG, JPEG, BMP, GIF | Zoomable image reader; animated GIFs retain animation. | Not required. |
| TIFF, TIF | All decoded scan pages, swipe navigation and zoom. | Not required. |
| SVG | SVG rendering with zoom; original colors retained. | Not required. |
| DOC, XLS, PPT | Imported originals are kept. Convert on Windows and share the resulting PDF to Android/web. | LibreOffice required. |
| MOBI | Classic, unencrypted MOBI with uncompressed or PalmDOC text, embedded images and file-position links. Uses the paginated ebook reader. | HUFF/CDIC, KF8 and unsupported encodings require Calibre conversion on Windows. DRM is unsupported. |
| EPS, PS | Imported originals are kept. Convert on Windows and share the resulting PDF. | Ghostscript required. |

## Local Windows conversion

Install the software needed for the files you use:

- [LibreOffice](https://www.libreoffice.org/download/download-libreoffice/) for Office/OpenDocument/RTF files.
- [Calibre for Windows](https://calibre-ebook.com/download_windows) for MOBI.
- [Ghostscript](https://www.ghostscript.com/releases/gsdnld.html) for EPS/PostScript.

Open the imported document in DocumentZ on Windows and select **Convert to PDF**. Standard installation folders and PATH are searched. For a portable installation, select **Choose executable** and select `soffice.exe`, `ebook-convert.exe`, or `gswin64c.exe`/`gswin32c.exe`. This selection is remembered locally.

Conversion uses a separate temporary job, an isolated LibreOffice profile where applicable, structured process arguments, a three-minute timeout, and a new PDF library copy. Original imported bytes are retained. No conversion service or document upload is used. Share the resulting PDF from its reader or library card, then import it on the Pixel.

The conversion adapter is implemented but live converter execution requires those programs installed on the user's Windows computer. They are not bundled with this app and have not been installed by this task.

## Fidelity and limits

- PDF variants are viewed as PDFs. The app does not certify PDF/A/X/UA compliance, expose the PDF/UA tag tree as a complete screen-reader structure, manage print color profiles, or interact with PDF/E 3D/CAD objects. Static fallback artwork can render where present.
- Direct Office/OpenDocument views preserve readable content, not original page geometry, exact fonts, charts, merged cells, formatting of spreadsheet values, slide animations, macros, calculations, or round-trip editing. Use Windows PDF conversion when page layout matters.
- RTF's direct view is text-only. HTML/MHTML do not run scripts, fetch remote artwork, or guarantee browser print-layout equivalence. Referenced companion files outside the imported HTML are not available; use embedded data images or saved MHTML.
- SVG features outside flutter_svg's supported SVG subset may render differently. Linked external assets, complex filters and browser-dependent artwork are not guaranteed.
- Document imports have no fixed application-level size cap. Memory and storage availability still apply. Expanded archive content remains limited to 200 MB. Very wide/large spreadsheets, highly repeated ODF ranges, and TIFFs over 200 pages or 80 million decoded pixels require smaller files or desktop PDF conversion.
- Non-PDF reading views support paragraph-based text marks where the HTML paragraph reader can select text. Cross-paragraph selection and marks over image-only files require the PDF workflow. Sharing an original does not embed app annotation overlays.

## Verification

Added tests for the complete extension list, original-byte retention, TXT/Markdown/UTF-16, RTF Unicode/destinations, DOCX styling/tables, XLSX sparse cells/shared strings, PPTX ordering, ODF text/sheets/slides, MHTML bundled images, multi-page TIFF and BMP decoding.

The latest user-run analyzer was clean and the suite passed 59 tests, including all format checks. The earlier OpenDocument text extraction and multi-page TIFF fixture failures are resolved. Two unrelated reader layout regressions were found and corrected; a fresh full run is pending. Representative real documents, SVG/image visual checks and live desktop converters remain pending.
