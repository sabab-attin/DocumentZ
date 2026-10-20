# PDF compression

DocumentZ compresses the existing PDF rather than rendering each page as a picture. Text that was selectable stays selectable. Links, forms, bookmarks, vectors and page dimensions stay in the document.

- **Original quality:** recompress eligible streams and use compact cross-reference storage where the PDF version permits it. Image pixels are unchanged.
- **Balanced, Small, Smallest:** also re-encode eligible RGB/grayscale images and reduce large image dimensions. Only a smaller image stream replaces its source. Text and vector graphics are not rasterized.
- All sizes are measured from complete output PDFs. Stronger settings never offer a larger file than a preceding setting. A result must be smaller than the original before Preview is enabled.

Already efficient PDFs may not get smaller. There is no universal minimum PDF size that every document can reach without losing content. Compression does not add OCR to scans. Protected and digitally signed documents are kept unchanged.

## Implementation

Work runs in an isolate. The existing Syncfusion PDF parser retains the original document graph. A small adapter recompresses supported Flate streams and optimizes embedded images; the Syncfusion version is pinned because this adapter uses its resource primitives. Replacing that dependency requires rerunning the preservation tests.

Transparency masks, nonidentity decode mappings, CMYK/ICC/indexed colour and unknown codecs retain their existing image encoding. Per-resource memory guards leave oversized/unsupported resources unchanged; they do not reject a document based on total file size. Resources outside the image optimizer can still receive lossless stream compression.

Before accepting a smaller output, DocumentZ reopens it and checks page count, geometry, rotation, extracted text, annotations and link targets, form-field count and bookmark count. Regression tests independently use PDFium to check selectable text, external and internal links, mixed page sizes, form values, embedded Unicode fonts, and pixel-identical lossless/transparency rendering.

Processing is local. No files are uploaded to an online compression service. The original is never overwritten by the compression step; the normal preview/save workflow creates the chosen output.

## References

- [qpdf: reducing file size](https://qpdf.readthedocs.io/en/12.2/cli.html): stream recompression, object streams and image optimization.
- [Adobe PDF 32000-1](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf): filters, image predictors, DCT colour transforms and resource dictionaries.
