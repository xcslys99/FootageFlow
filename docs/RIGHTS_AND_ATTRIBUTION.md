# Rights and Attribution

FootageFlow helps preserve source information. It does not make legal decisions, grant permissions, or infer a license that the Provider did not supply.

## Rights states

- **Rights known**: The Provider supplied a recognizable rights or license statement.
- **Attribution required**: The Provider metadata explicitly says attribution is required.
- **Public Domain**: The specific item metadata explicitly identifies it as Public Domain.
- **Rights unknown**: The Provider did not supply enough information to classify the item.
- **Restricted**: The source reports a restriction that prevents FootageFlow from treating the item as directly reusable.

Provider identity never determines an item's rights by itself. Internet Archive, NASA, Library of Congress, National Archives, Europeana, and Wikimedia items are not automatically Public Domain.

## Result actions

- **Open Original** opens the current source page so the user can verify permissions and context.
- **Copy Source** copies available title, Provider, creator, and source URL fields.
- **Copy Attribution** formats only Provider-supplied creator, license, license URL, and attribution fields.

Missing fields remain explicit. FootageFlow does not fill them with “free to use,” “commercial use allowed,” or Public Domain guesses.

## Source sidecars

Every successful download creates matching `.source.txt` and `.source.json` files beside the media. Depending on available metadata, they record:

- title and Provider asset ID
- Provider and original source page
- original media URL
- creator or uploader
- license or rights statement and URL
- rights status and an unknown-rights warning when needed
- search keyword
- download date
- project and script segment
- selected Link Downloader format, output preset, or clip range

Sensitive URL query values are redacted. Sidecars document the source information known at download time; they do not replace the current original page or legal review.

## Before publishing

1. Open the original source page.
2. Confirm the item identity and current availability.
3. Read the actual license, rights statement, usage restrictions, and attribution requirements.
4. Confirm that your intended commercial, editorial, educational, or derivative use is permitted.
5. Keep the sidecars and any required credits with the project.

A successful search, preview, or download is not permission to reuse media.

## Repository license

The [MIT License](../LICENSE) applies only to FootageFlow's source code. It does not apply to media, thumbnails, Provider metadata, Provider brands, or third-party tools found or used through the application.

FootageFlow is not affiliated with or endorsed by the listed Providers. This product uses the National Archives Catalog API but is not endorsed or certified by the National Archives and Records Administration.

See [Provider modes](PROVIDERS.md), [Privacy](../PRIVACY.md), and the [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).
