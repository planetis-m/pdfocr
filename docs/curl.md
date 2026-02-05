# Curl Module API Documentation

**Module:** `pdfocr.curl`

This module provides a high-level wrapper around libcurl for making HTTP requests.

## Types

### CurlEasy
```nim
CurlEasy = object
```
Represents an easy handle for performing HTTP requests.

### CurlMulti
```nim
CurlMulti = object
```
Represents a multi handle for multiplexing multiple easy handles.

### CurlSlist
```nim
CurlSlist = object
```
Represents a list of HTTP headers.

## Procedures

### Global Initialization

#### `initCurlGlobal()`
```nim
proc initCurlGlobal(flags: culong = CURL_GLOBAL_DEFAULT)
```
Initializes the libcurl library globally.

- **Parameters:**
  - `flags`: Initialization flags (default: `CURL_GLOBAL_DEFAULT`)
- **Raises:** `IOError` if initialization fails

#### `cleanupCurlGlobal()`
```nim
proc cleanupCurlGlobal()
```
Cleans up global libcurl resources.

### Error Handling

#### `checkCurl()`
```nim
proc checkCurl(code: CURLcode; context: string)
```
Checks a CURLcode and raises an IOError if it indicates an error.

#### `checkCurlMulti()`
```nim
proc checkCurlMulti(code: CURLMcode; context: string)
```
Checks a CURLMcode and raises an IOError if it indicates an error.

### Easy Handle Management

#### `initEasy()`
```nim
proc initEasy(): CurlEasy
```
Creates a new easy handle for making HTTP requests.

- **Returns:** `CurlEasy` handle
- **Raises:** `IOError` if handle creation fails

#### `setUrl()`
```nim
proc setUrl(easy: var CurlEasy; url: string)
```
Sets the URL for the HTTP request.

#### `setWriteCallback()`
```nim
proc setWriteCallback(easy: var CurlEasy; cb: curl_write_callback; userdata: pointer)
```
Sets the callback function for handling response data.

#### `setPostFields()`
```nim
proc setPostFields(easy: var CurlEasy; data: string)
```
Sets the POST data for the request.

#### `setHeaders()`
```nim
proc setHeaders(easy: var CurlEasy; headers: CurlSlist)
```
Sets HTTP headers for the request.

#### `setTimeoutMs()`
```nim
proc setTimeoutMs(easy: var CurlEasy; timeoutMs: int)
```
Sets the total timeout for the request in milliseconds.

#### `setConnectTimeoutMs()`
```nim
proc setConnectTimeoutMs(easy: var CurlEasy; timeoutMs: int)
```
Sets the connection timeout in milliseconds.

#### `setSslVerify()`
```nim
proc setSslVerify(easy: var CurlEasy; verifyPeer: bool; verifyHost: bool)
```
Configures SSL certificate verification.

#### `setAcceptEncoding()`
```nim
proc setAcceptEncoding(easy: var CurlEasy; encoding: string)
```
Sets the Accept-Encoding header (e.g., "gzip, deflate").

#### `reset()`
```nim
proc reset(easy: var CurlEasy)
```
Resets an easy handle to default libcurl state for safe reuse.

#### `setPrivate()`
```nim
proc setPrivate(easy: var CurlEasy; data: pointer)
```
Associates user data with the easy handle for later retrieval.

#### `getPrivate()`
```nim
proc getPrivate(easy: CurlEasy): pointer
```
Retrieves user data previously associated via `setPrivate`.

#### `perform()`
```nim
proc perform(easy: var CurlEasy)
```
Executes the configured HTTP request.

#### `responseCode()`
```nim
proc responseCode(easy: CurlEasy): int
```
Returns the HTTP response code.

#### `addHeader()`
```nim
proc addHeader(list: var CurlSlist; headerLine: string)
```
Adds a header line to the header list.

### Multi Handle Management

#### `initMulti()`
```nim
proc initMulti(): CurlMulti
```
Creates a new multi handle for managing concurrent easy handles.

#### `addHandle()`
```nim
proc addHandle(multi: var CurlMulti; easy: CurlEasy)
```
Adds an easy handle to a multi handle.

#### `removeHandle()`
```nim
proc removeHandle(multi: var CurlMulti; easy: CurlEasy)
```
Removes an easy handle from a multi handle.

#### `perform()`
```nim
proc perform(multi: var CurlMulti): int
```
Performs transfers on all added handles and returns the number of running handles.

#### `poll()`
```nim
proc poll(multi: var CurlMulti; timeoutMs: int): int
```
Waits for activity and returns the number of file descriptors with activity.

#### `tryInfoRead()`
```nim
proc tryInfoRead(multi: var CurlMulti; msg: var CURLMsg; msgsInQueue: var int): bool
```
Reads a completed transfer message into `msg`, updates `msgsInQueue`, and returns `true` if a message was read.

## Usage Example

```nim
import pdfocr/curl

initCurlGlobal()
try:
  var easy = initEasy()
  easy.setUrl("https://example.com")
  easy.setTimeoutMs(5000)
  easy.perform()
  let code = easy.responseCode()
  discard code
finally:
  cleanupCurlGlobal()
```
