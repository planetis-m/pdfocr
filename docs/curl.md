# Curl Module API Documentation

**Module:** `pdfocr.curl`

This module provides a high-level wrapper around libcurl for making HTTP requests.

## Types

### CurlEasy
```nim
CurlEasy = object
  raw*: CURL
  postData*: string
  errorBuf*: array[256, char]
```
Represents an easy handle for performing HTTP requests.

### CurlSlist
```nim
CurlSlist = object
  raw*: ptr curl_slist
```
Represents a list of HTTP headers.

## Procedures

### Global Initialization

#### `initCurlGlobal()`
```nim
proc initCurlGlobal(flags: culong = CURL_GLOBAL_DEFAULT) {.raises: [IOError], tags: [], forbids: [].}
```
Initializes the libcurl library globally.

- **Parameters:**
  - `flags`: Initialization flags (default: `CURL_GLOBAL_DEFAULT`)
- **Raises:** `IOError` if initialization fails

#### `cleanupCurlGlobal()`
```nim
proc cleanupCurlGlobal() {.raises: [], tags: [], forbids: [].}
```
Cleans up global libcurl resources.

### Easy Handle Management

#### `initEasy()`
```nim
proc initEasy(): CurlEasy {.raises: [IOError], tags: [], forbids: [].}
```
Creates a new easy handle for making HTTP requests.

- **Returns:** `CurlEasy` handle
- **Raises:** `IOError` if handle creation fails

#### `close()`
```nim
proc close(easy: var CurlEasy) {.raises: [], tags: [], forbids: [].}
```
Closes and cleans up an easy handle.

### Request Configuration

#### `setUrl()`
```nim
proc setUrl(easy: var CurlEasy; url: string) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the URL for the HTTP request.

#### `setWriteCallback()`
```nim
proc setWriteCallback(easy: var CurlEasy; cb: curl_write_callback; userdata: pointer) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the callback function for handling response data.

#### `setPostFields()`
```nim
proc setPostFields(easy: var CurlEasy; data: string) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the POST data for the request.

#### `setHeaders()`
```nim
proc setHeaders(easy: var CurlEasy; headers: CurlSlist) {.raises: [IOError], tags: [], forbids: [].}
```
Sets HTTP headers for the request.

#### `setTimeoutMs()`
```nim
proc setTimeoutMs(easy: var CurlEasy; timeoutMs: int) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the total timeout for the request in milliseconds.

#### `setConnectTimeoutMs()`
```nim
proc setConnectTimeoutMs(easy: var CurlEasy; timeoutMs: int) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the connection timeout in milliseconds.

#### `setSslVerify()`
```nim
proc setSslVerify(easy: var CurlEasy; verifyPeer: bool; verifyHost: bool) {.raises: [IOError], tags: [], forbids: [].}
```
Configures SSL certificate verification.

- **Parameters:**
  - `verifyPeer`: Whether to verify the peer certificate
  - `verifyHost`: Whether to verify the host certificate

#### `setAcceptEncoding()`
```nim
proc setAcceptEncoding(easy: var CurlEasy; encoding: string) {.raises: [IOError], tags: [], forbids: [].}
```
Sets the Accept-Encoding header (e.g., "gzip, deflate").

### Performing Requests

#### `perform()`
```nim
proc perform(easy: var CurlEasy) {.raises: [IOError], tags: [], forbids: [].}
```
Executes the configured HTTP request.

- **Raises:** `IOError` if the request fails

#### `responseCode()`
```nim
proc responseCode(easy: CurlEasy): int {.raises: [IOError], tags: [], forbids: [].}
```
Returns the HTTP response code.

- **Returns:** HTTP status code (e.g., 200, 404, 500)

### Header List Management

#### `addHeader()`
```nim
proc addHeader(list: var CurlSlist; headerLine: string) {.raises: [IOError], tags: [], forbids: [].}
```
Adds a header line to the header list.

- **Parameters:**
  - `list`: The header list
  - `headerLine`: Header string in format "Name: Value"

#### `free()`
```nim
proc free(list: var CurlSlist) {.raises: [], tags: [], forbids: [].}
```
Frees the header list and its resources.

## Error Handling

### `checkCurl()`
```nim
proc checkCurl(code: CURLcode; context: string) {.raises: [IOError], tags: [], forbids: [].}
```
Checks a CURLcode and raises an IOError if it indicates an error.

- **Parameters:**
  - `code`: The CURLcode to check
  - `context`: Context description for error messages

## Usage Example

```nim
# Initialize
initCurlGlobal()

var easy = initEasy()
easy.setUrl("https://example.com")
easy.setTimeoutMs(5000)

# Set up headers
var headers: CurlSlist
headers.addHeader("Content-Type: application/json")
easy.setHeaders(headers)

# Perform request
easy.perform()
let code = easy.responseCode()

# Cleanup
easy.close()
headers.free()
cleanupCurlGlobal()
```
