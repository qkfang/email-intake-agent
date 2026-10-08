using Azure.Core;
using Microsoft.Identity.Web;
using System.Security.Claims;

namespace EmailIntake.Web.Services;

public sealed class UserTokenCredential(ITokenAcquisition tokenAcquisition, ClaimsPrincipal user) : TokenCredential
{
    public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken) =>
        throw new NotSupportedException("Use asynchronous user-token acquisition.");

    public override async ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = await tokenAcquisition.GetAuthenticationResultForUserAsync(
            [FoundryService.ResponsesScope], user: user);
        return new AccessToken(result.AccessToken, result.ExpiresOn);
    }
}
