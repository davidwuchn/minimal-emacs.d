λ(url,f). web_fetch | url:URL | f:format(opt) | ret:content

# WebFetch - Fetch Web Page Content

## Purpose
Fetch and extract content from a web URL. Converts web pages to markdown or plain text.

## When to Use
- Reading documentation from web
- Fetching API documentation
- Getting latest information not in training data
- Checking external resources

## Usage
```
WebFetch{url: "https://example.com/docs", format?: "markdown"}
```

## Parameters
- `url` (required): Full URL to fetch (must include http:// or https://)
- `format` (optional): Output format - "markdown" (default) or "text"

## Returns
- Page content in requested format
- Error message if fetch failed

## Examples
```
# Fetch documentation page
WebFetch{url: "https://docs.python.org/3/library/asyncio.html", format: "markdown"}
→ Returns: Markdown-formatted content from Python asyncio docs

# Fetch as plain text
WebFetch{url: "https://example.com/api", format: "text"}
→ Returns: Plain text content
```

## Dependencies
- **Required**: Internet connection
- **Required**: Valid URL with http/https protocol
- **Optional**: None

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "URL invalid" | Missing http/https | Add protocol to URL |
| "Fetch failed" | Network error | Check internet connection |
| "Timeout" | Slow/unreachable site | Try again or use alternative source |
| "Access denied" | Site blocks bots | Use WebSearch instead |

## Supported Formats
- **markdown**: Best for documentation, preserves structure (default)
- **text**: Plain text, removes all formatting

## Notes
- Respects robots.txt
- Rate-limited to avoid overloading servers
- Large pages may be truncated
- JavaScript-rendered content may not be available
- Use WebSearch for finding information, WebFetch for reading specific URLs

## Related Tools
- `WebSearch` - Search the web for information
- `YouTube` - Fetch YouTube video transcripts
