λ(path, original, replacement). InlineDiffPreview | diff:unified | req:review-changes | ret:callback-result
λ(files). BatchPreview | diff:unified | req:review-multiple | ret:callback-result
λ(path, content). SyntaxPreview | read:syntax | req:show-snippet | ret:success

# Preview Tools - Interactive Code Review

Use these tools to show the user interactive previews of code changes, file creations, or multi-file refactors before fully committing or saving them.

## Availability
- `InlineDiffPreview`: :nucleus, :snippets

## 1. InlineDiffPreview
Use this tool to show the user an interactive, syntax-highlighted side-by-side or unified diff preview before applying changes to a single file.
- `path` (string, required): The absolute path to the file being modified.
- `original` (string, required): The complete, original content of the file.
- `replacement` (string, required): The complete, proposed new content of the file.

## 2. BatchPreview
Use this tool to show the user a single, consolidated diff preview for modifications spanning multiple files simultaneously.
- `files` (array, required): A list of file change objects. Each object should have the path, original content, and replacement content.
Use this during refactoring instead of prompting the user for every single file individually.

## 3. SyntaxPreview
Use this tool to display a syntax-highlighted code snippet or a new file preview to the user in a temporary buffer.
- `path` (string, required): The file path (used to determine the correct syntax highlighting language, e.g. "foo.py" will use python-mode).
- `content` (string, required): The source code or content to display.
Use this when you want to show the user code (a snippet, script, or proposed new file) but you do not want to execute it or save it yet.