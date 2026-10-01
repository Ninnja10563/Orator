using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using System.IO.Compression;
var failed = false;
foreach (var path in args) {
    using var presentation = PresentationDocument.Open(path, false);
    var errors = new OpenXmlValidator(FileFormatVersions.Office2019).Validate(presentation).ToList();
    foreach (var error in errors) Console.Error.WriteLine($"{path}: {error.Part?.Uri} {error.Path?.XPath}: {error.Description}");
    failed |= errors.Count > 0;
    using var archive = ZipFile.OpenRead(path);
    foreach (var entry in archive.Entries.Where(e => e.FullName.EndsWith(".xlsx"))) {
        using var memory = new MemoryStream(); using (var source = entry.Open()) source.CopyTo(memory); memory.Position = 0;
        using var workbook = SpreadsheetDocument.Open(memory, false);
        var workbookErrors = new OpenXmlValidator().Validate(workbook).ToList();
        foreach (var error in workbookErrors) Console.Error.WriteLine($"{entry.FullName}: {error.Description}");
        failed |= workbookErrors.Count > 0;
    }
    Console.WriteLine($"Checked {path}: {errors.Count} presentation schema errors");
}
return failed ? 1 : 0;
