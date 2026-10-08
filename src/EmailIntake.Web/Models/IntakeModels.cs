using System.ComponentModel.DataAnnotations;

namespace EmailIntake.Web.Models;

public sealed class EmailInput
{
    [Required, StringLength(500)]
    public string Subject { get; set; } = "";

    [Required, EmailAddress, StringLength(320)]
    public string Sender { get; set; } = "";

    [Required, StringLength(50_000)]
    public string Body { get; set; } = "";
}

public sealed record AttachmentEvidence(string FileName, string Content, string Status);

public sealed record IntakeResult(
    string Category,
    double Confidence,
    string Summary,
    string SuggestedAction,
    bool RequiresHumanReview,
    List<DocumentResult> Attachments,
    List<string> Evidence,
    List<string> Warnings);

public sealed record DocumentResult(
    string FileName,
    string DocumentType,
    string Summary,
    Dictionary<string, string> Fields,
    List<string> MissingFields);
