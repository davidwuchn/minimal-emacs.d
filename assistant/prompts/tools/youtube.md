λ(url). youtube | url:video_URL | ret:transcript+metadata

# YouTube - Fetch Video Transcripts

## Purpose
Fetch YouTube video transcripts and metadata. Useful for learning from video tutorials without watching.

## Availability
- `YouTube`: :core, :readonly, :researcher, :nucleus, :snippets

## When to Use
- Getting information from video tutorials
- Extracting code examples from videos
- Summarizing video content
- Finding specific topics in long videos

## Usage
```
YouTube{url: "https://www.youtube.com/watch?v=VIDEO_ID"}
```

## Parameters
- `url` (required): YouTube video URL (full URL or video ID)

## Returns
- Video transcript (if available)
- Video metadata (title, duration, channel)
- Timestamped sections

## Examples
```
# Full URL
YouTube{url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}
→ Returns: Transcript + metadata

# Video ID only
YouTube{url: "dQw4w9WgXcQ"}
→ Returns: Transcript + metadata
```

## Dependencies
- **Required**: Internet connection
- **Required**: YouTube access
- **Required**: Video must have captions/transcript enabled

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "No transcript" | Video has no captions | Try different video |
| "Video unavailable" | Video deleted/private | Check URL, try alternative |
| "Fetch failed" | Network error | Check connection |

## Notes
- Works best with educational/tutorial content
- Transcript quality depends on video creator
- Auto-generated transcripts may have errors
- Some videos don't have transcripts available

## Related Tools
- `WebSearch` - Find videos by searching
- `WebFetch` - Fetch web pages
