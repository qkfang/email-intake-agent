using Azure.Core;
using Azure.Identity;
using EmailIntake.Web.Services;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddApplicationInsightsTelemetry();
}
var authEnabled = !string.IsNullOrWhiteSpace(builder.Configuration["AzureAd:ClientId"]);
if (!authEnabled && !builder.Environment.IsDevelopment())
{
    throw new InvalidOperationException("Configure AzureAd:ClientId before hosting email intake outside Development.");
}

if (authEnabled)
{
    builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
        .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"))
        .EnableTokenAcquisitionToCallDownstreamApi([FoundryService.ResponsesScope])
        .AddInMemoryTokenCaches();
    builder.Services.AddControllersWithViews().AddMicrosoftIdentityUI();
}
builder.Services.AddRazorPages(options =>
{
    if (authEnabled)
    {
        options.Conventions.AuthorizeFolder("/");
        options.Conventions.AllowAnonymousToPage("/Error");
    }
});
builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = IntakeService.MaxTotalBytes + 1024 * 1024;
    options.ValueLengthLimit = IntakeService.MaxBodyCharacters * 4;
});
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = IntakeService.MaxTotalBytes + 1024 * 1024);
builder.Services.AddSingleton<TokenCredential>(new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    ExcludeManagedIdentityCredential = string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID"))
}));
builder.Services.AddSingleton<FoundryService>();
builder.Services.AddSingleton<IntakeService>();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("intake", context => RateLimitPartition.GetConcurrencyLimiter(
        context.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value
            ?? context.Connection.RemoteIpAddress?.ToString() ?? "local",
        _ => new ConcurrencyLimiterOptions { PermitLimit = 2, QueueLimit = 0 }));
});

var app = builder.Build();
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}
app.UseHttpsRedirection();
app.UseRouting();
if (authEnabled)
{
    app.UseAuthentication();
}
app.UseAuthorization();
app.UseRateLimiter();
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
    if (context.Request.Path == "/")
    {
        context.Response.Headers.CacheControl = "no-store";
    }
    await next();
});
app.MapStaticAssets();
app.MapRazorPages().RequireRateLimiting("intake").WithStaticAssets();
if (authEnabled)
{
    app.MapControllers();
}
app.MapGet("/health", () => Results.Ok(new { status = "healthy" })).AllowAnonymous();
app.Run();
