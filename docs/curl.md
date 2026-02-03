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

### CurlMulti
```nim
CurlMulti = object
  raw*: CURLM
```
Represents a multi handle for multiplexing multiple easy handles.

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

### Error Handling

#### `checkCurl()`
```nim
proc checkCurl(code: CURLcode; context: string) {.raises: [IOError], tags: [], forbids: [].}
```
Checks a CURLcode and raises an IOError if it indicates an error.

#### `checkCurlMulti()`
```nim
proc checkCurlMulti(code: CURLMcode; context: string) {.raises: [IOError], tags: [], forbids: [].}
```
Checks a CURLMcode and raises an IOError if it indicates an error.

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

### Multi Handle Management

#### `initMulti()`
```nim
proc initMulti(): CurlMulti {.raises: [IOError], tags: [], forbids: [].}
```
Creates a new multi handle for managing concurrent easy handles.

#### `close()`
```nim
proc close(multi: var CurlMulti) {.raises: [IOError], tags: [], forbids: [].}
```
Closes and cleans up a multi handle.

#### `addHandle()`
```nim
proc addHandle(multi: var CurlMulti; easy: CurlEasy) {.raises: [IOError], tags: [], forbids: [].}
```
Adds an easy handle to a multi handle.

#### `removeHandle()`
```nim
proc removeHandle(multi: var CurlMulti; easy: CurlEasy) {.raises: [IOError], tags: [], forbids: [].}
```
Removes an easy handle from a multi handle.

#### `perform()`
```nim
proc perform(multi: var CurlMulti): int {.raises: [IOError], tags: [], forbids: [].}
```
Performs transfers on all added handles and returns the number of running handles.

#### `poll()`
```nim
proc poll(multi: var CurlMulti; timeoutMs: int): int {.raises: [IOError], tags: [], forbids: [].}
```
Waits for activity and returns the number of file descriptors with activity.

#### `tryInfoRead()`
```nim
proc tryInfoRead(multi: var CurlMulti; msg: var CURLMsg; msgsInQueue: var int): bool {.raises: [], tags: [], forbids: [].}
```
Reads a completed transfer message into `msg`, updates `msgsInQueue`, and returns `true` if a message was read.

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

## Usage Example

```nim
# Initialize
initCurlGlobal()

var easy = initEasy()
var multi = initMulti()
easy.setUrl("https://example.com")
easy.setTimeoutMs(5000)

# Set up headers
var headers: CurlSlist
headers.addHeader("Content-Type: application/json")
easy.setHeaders(headers)

# Add to multi and poll
multi.addHandle(easy)
discard multi.poll(0)
var msgs = 0
var msg: CURLMsg
while multi.tryInfoRead(msg, msgs):
  discard msg
easy.perform()
let code = easy.responseCode()
multi.removeHandle(easy)

# Cleanup
easy.close()
multi.close()
headers.free()
cleanupCurlGlobal()
```
