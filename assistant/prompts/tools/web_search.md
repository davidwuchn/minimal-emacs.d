λ(q,u,t). web_search | q:query | u:urls(opt) | t:think(opt) | ret:results

# WebSearch - Search the Web

## Purpose
Search the web using DuckDuckGo and Google. Returns real-time information with source citations.

## When to Use
- Finding current information not in training data
- Researching latest developments
- Finding documentation or tutorials
- Verifying facts with sources

## Usage
```
WebSearch{query: "python asyncio best practices 2024", thinking?: true}
WebSearch{query: "rust async tutorial", urls: ["https://rust-lang.org"]}
```

## Parameters
- `query` (required): Search query string
- `urls` (optional): Array of specific URLs to analyze
- `thinking` (optional): If true, use deep analysis mode (default: false)

## Returns
- Search results with source URLs and citations
- Analyzed content if URLs provided

## Examples
```
# General web search
WebSearch{query: "python 3.12 new features"}
→ Returns: List of search results with URLs and snippets

# Analyze specific URLs
WebSearch{query: "async best practices", urls: ["https://docs.python.org/3/library/asyncio.html"]}
→ Returns: Analyzed content from specified URLs

# Deep analysis mode
WebSearch{query: "rust vs go performance", thinking: true}
→ Returns: Detailed analysis with multiple sources
```

## Dependencies
- **Required**: Internet connection
- **Required**: Search engine access (DuckDuckGo/Google)
- **Optional**: Specific URLs for targeted analysis

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "No results" | Query too specific | Broaden search terms |
| "Search failed" | Network error | Check internet connection |
| "Rate limited" | Too many searches | Wait and retry |

## Search Tips
1. **Be specific**: Include version numbers, dates for current info
2. **Use quotes**: "exact phrase" for exact matches
3. **Site search**: Add "site:github.com" to search specific sites
4. **Thinking mode**: Enable for complex queries needing analysis

## Notes
- Results include source citations
- Thinking mode provides deeper analysis but slower
- Rate-limited to avoid abuse
- Use WebFetch to read full content from specific URLs

## Related Tools
- `WebFetch` - Fetch content from specific URLs
- `YouTube` - Search and fetch YouTube videos
