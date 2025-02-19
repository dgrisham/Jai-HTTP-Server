

// #load "websocket.jai";

#if OS == .WINDOWS #load "windows.jai";
#if OS == .LINUX   #load "linux.jai";

// the main entry point is http_listen, which is defined in linux.jai and windows.jai




// todo: this method of looping through handlers is slow @perf
handlers: [..] Handler;

Handler :: struct {
  method: METHOD;
  path: Router_Path;
  cb: (*Request)->();
}

Router_Path :: struct {
    parts: [..] Path_Element;
}

Path_Element :: struct {
    word     : string;
    is_param : bool;
}

parse_router_path :: (s: string) -> Router_Path
{
    parts := split(s, "/");
    path: Router_Path;
    array_reserve(*path.parts, parts.count);
    for parts
    {
        if it == "" continue;

        path_part: Path_Element;
        path_part.word     = it;
        path_part.is_param = contains(it, #char ":");

        array_add(*path.parts, path_part);
    }

    return path;
}

get     :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.GET,     cb=cb, path=parse_router_path(path)}); }
post    :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.POST,    cb=cb, path=parse_router_path(path)}); }
put     :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.PUT,     cb=cb, path=parse_router_path(path)}); }
delete  :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.DELETE,  cb=cb, path=parse_router_path(path)}); }
any     :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.ANY,     cb=cb, path=parse_router_path(path)}); }
options :: (path: string, cb: (*Request)->()) {array_add(*handlers, .{method=.OPTIONS, cb=cb, path=parse_router_path(path)}); }

// Response_Writer is for more fine-grained control of the http response
// (e.g. flushing headers, writing SSE events to the body without closing the connection, etc.)

Response_Writer :: struct {
    socket  : MySocket;
    builder : String_Builder;
};

New_Response_Writer :: (request: *Request, status_code := 200) -> Response_Writer
{
    w: Response_Writer;
    w.socket = request.socket;

    append(*w.builder, tprint("HTTP/1.1 % %", status_code, status_code_string(status_code)));
    append(*w.builder, CRLF);

    write_headers(
        w,
        .{"Content-Security-Policy"     , "allow-same-origin"            },
        .{"Access-Control-Allow-Origin" ,  "*"                           },
        .{"Access-Control-Allow-Methods", "GET"                          },
        .{"Access-Control-Allow-Headers", "Origin, Methods, Content-Type"},
    );

    return w;
}

// headers

Header :: struct {
    key, value: string;
};

write_headers :: (using w: Response_Writer, headers: .. Header)
{
    for headers
    {
        append(*builder, tprint("%: %", it.key, it.value));
        append(*builder, CRLF);
    }
}

flush_headers :: (using w: Response_Writer) -> bool
{
    // add final CRLF to delineate headers from body
    append(*builder, CRLF);

    return mysocket_write(socket, builder_to_string(*builder));
}

// body

append :: (using w: Response_Writer, data: .. string)
{
    for data  append(*builder, it);
}

flush :: (using w: Response_Writer) -> bool
{
    return mysocket_write(socket, builder_to_string(*builder));
}

finish :: (using w: Response_Writer)
{
    mysocket_close(socket);
}

// Response

Response :: struct {

    status_code     := 200;

    socket          : MySocket;
    headers         : [..] Header;
    content_encoding: string;
    body            : string;
}

add_headers :: (response: Response, headers: .. Header)
{
    for headers array_add(*response.headers, it);
}

New_Response :: (request: *Request) -> Response
{
    response: Response;
    response.socket = request.socket;

    add_headers(
        *response,
        .{"Content-Security-Policy"     , "allow-same-origin"            },
        .{"Access-Control-Allow-Origin" ,  "*"                           },
        .{"Access-Control-Allow-Methods", "GET"                          },
        .{"Access-Control-Allow-Headers", "Origin, Methods, Content-Type"},
    );

    return response;
}

CRLF :: "\r\n";

send_response :: (request: *Request, response: Response)
{
    response_builder: String_Builder;
    init_string_builder(*response_builder);

    using response;

    append(*response_builder, tprint("HTTP/1.1 % %", status_code, status_code_string(status_code)));
    append(*response_builder, CRLF);

    append(*response_builder, tprint("Content-Length: %", body.count));
    append(*response_builder, CRLF);

    for headers
    {
        append(*response_builder, tprint("%: %", it.key, it.value));
        append(*response_builder, CRLF);
    }

    append(*response_builder, CRLF);
    append(*response_builder, body);

    mysocket_write(request.socket, builder_to_string(*response_builder));
    mysocket_close(*request.socket);
}

status_code_string :: (status: int) -> string
{
    if status == {
        case 100; return "Continue";
        case 101; return "Switching Protocols";
        case 200; return "OK";
        case 201; return "Created";
        case 202; return "Accepted";
        case 203; return "Non-Authoritative Information";
        case 204; return "No Content";
        case 205; return "Reset Content";
        case 206; return "Partial Content";
        case 300; return "Multiple Choices";
        case 301; return "Moved Permanently";
        case 302; return "Found";
        case 303; return "See Other";
        case 304; return "Not Modified";
        case 307; return "Temporary Redirect";
        case 308; return "Permanent Redirect";
        case 400; return "Bad Request";
        case 401; return "Unauthorized";
        case 403; return "Forbidden";
        case 404; return "Not Found";
        case 405; return "Method Not Allowed";
        case 408; return "Request Timeout";
        case 409; return "Conflict";
        case 410; return "Gone";
        case 413; return "Payload Too Large";
        case 414; return "URI Too Long";
        case 415; return "Unsupported Media Type";
        case 418; return "I'm a teapot";
        case 429; return "Too Many Requests";
        case 500; return "Internal Server Error";
        case 501; return "Not Implemented";
        case 502; return "Bad Gateway";
        case 503; return "Service Unavailable";
        case 504; return "Gateway Timeout";
        case 505; return "HTTP Version Not Supported";
        case;     return "Server error";
    }
}

send_html :: #bake_arguments build_and_send_response(content_type="text/html");
send_text :: #bake_arguments build_and_send_response(content_type="text/plain");
send_json :: #bake_arguments build_and_send_response(content_type="application/json");

build_and_send_response :: (request: *Request, body: string, status_code: u16 = 200, content_type := "", content_encoding: string = "")
{
    response: Response;
    response.status_code      = status_code;
    response.content_encoding = content_encoding;
    response.body             = body;
    add_headers(*response, .{"Content-Type", content_type}, .{"Server", "Jai"});

    send_response(request, response);
}

// send_file :: (request: *Request, raw_filename: string) {
//   filename := normalize_filename(raw_filename);

//   file_cache_record, success := file_cache_get_or_create(filename);
//   if !success return;

//   // for very small files, it's possible that brotli encoding is longer than the raw content.
//   // in that case the brotli api will return the brotli encoding as ""
//   // and so we will return the raw content instead, even though the client accepts br encoding
//   are_we_returning_br := does_request_accept_encoding(request, "br") && file_cache_record.brotli != "";

//   content := ifx are_we_returning_br then file_cache_record.brotli else file_cache_record.rawcontent;
//   content_encoding := ifx are_we_returning_br then "br" else "";
//   content_type := extension2contenttype(filename);
//   send_response(request, content, content_type=content_type, content_encoding=content_encoding);
// }


parseheaders :: true;
Request :: struct {
  #as socket      : MySocket;

  raw             : string; // entire raw http request
  body            : string; // pointer into raw
  raw_path        : string; // pointer into raw

  path            : Request_Path;

  content_length  : u32;
  method          : METHOD;
  // websocket_key   : string;
  accept_encoding : string;

  path_params     : Table(string, string);
  #if parseheaders {
    headers       : Table(string, string);
  }

  cookies         : Table(string, string);
  err             : bool;

  #if OS == .LINUX {
    buffercursor     : u32;
    startofline      : u32;
  }

  get_param :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.path_params, name);
    if !found return "";
    return val;
  }
}
operator == :: inline (a: Request, b: Request) -> bool { return a.socket == b.socket; }

does_request_accept_encoding :: (request: *Request, encoding: string) -> bool {
  if !request.accept_encoding return false;
  for encoding: split(request.accept_encoding, ",") {
    if trim(encoding, " ") == encoding return true;
  }
  return false;
}

handle_request :: (request: *Request)
{
  is_path_match :: (router_path: Router_Path, request: Request) -> bool
  {
    if router_path.parts.count != request.path.words.count
        return false;

    for router_path_part: router_path.parts
    {
        if router_path_part.is_param
            continue;
        if router_path_part.word != request.path.words[it_index]
            return false;
    }

    return true;
  }

  push_allocator(temp);
  defer reset_temporary_storage();

  // push_context { log("Have request on: %", request.path); }

  // let the user's middleware handle the request!
  for middleware: handlers
  {
    if !is_path_match(middleware.path, request)
        continue;

    // table_reset(*request.path_params); // maybe this should happen somewhere else?
    for route_part: middleware.path.parts
    {
        if !route_part.is_param continue;
        table_add(*request.path_params, route_part.word, request.path.words[it_index]);
    }

    middleware.cb(request);

    return;
  }

  // if none of the middleware responded to this request, 404
  push_context {
      send_html(request, tprint("<pre>Cannot % %</pre>", request.method, request.raw_path), status_code=404);
  }
}

cwd: string;
the_static_folder_to_serve: string;
static :: (folder: string) {
  assert(folder.count > 0, "folder to serve can't be an empty string");
  assert(the_static_folder_to_serve.count == 0, "you can't currently static serve more than 1 folder");

  cwd = copy_string(get_working_directory());
  the_static_folder_to_serve = folder;

  get("*", (request: *Request) {;

    // if the path ends wht a / then we consider it a folder, and we'll add index.html to the end of the path to load that.
    path: string;
    if ends_with(request.raw_path, "/") {
      path = tjoin(cwd, "/", the_static_folder_to_serve, request.raw_path, "index.html");
    } else {
      path = tjoin(cwd, "/", the_static_folder_to_serve, request.raw_path);
    }

    send_file(request, path);
  });
}




// when we cache a file, we store both the raw content and also the brotli compressed version of it
File_Cache_Record :: struct {rawcontent: string; brotli: string; }
file_cache: Table(string, File_Cache_Record);

file_cache_get_or_create :: (filename: string) -> File_Cache_Record, bool {

  #if OS != .WINDOWS { // don't actually cache files on windows. for better development experience
    record, found := table_find(*file_cache, filename);
    if found then return record, true;
  }

  filetext, success := read_entire_file(filename);
  if !success return .{}, false;


  // just incase filename is in temporary storage
  // we have to leak a copy of it here to store in the table that won't turn to garbage
  filename_allocated := copy_string(filename);
  file_cache_record := table_set(*file_cache, filename_allocated, .{});
  file_cache_record.rawcontent = filetext;

  content_type := extension2contenttype(filename);
  is_filecontent_text := find_index_from_left("content_type", "text/") == 0;

  #import,dir "modules/brotli";
  compressed := ifx is_filecontent_text then brotli_compress_text(filetext) else brotli_compress(filetext);
  file_cache_record.brotli = compressed;

  return file_cache_record, true;
}






METHOD :: enum u8 {ANY; GET; POST; PUT; DELETE; OPTIONS;}
to_METHOD :: (str: string) -> METHOD {
  if str == {
    case "GET";     return .GET;
    case "POST";    return .POST;
    case "PUT";     return .PUT;
    case "DELETE";  return .DELETE;
    case "OPTIONS"; return .OPTIONS;
    case;           return .ANY;
  }
}


// Content-Type aka MIME type
extension2contenttype :: (filename: string) -> string {
  index_of_dot := find_index_from_right(filename, ".");
  if index_of_dot == -1 return "text/html";

  extension := substr(filename, index_of_dot, filename.count-index_of_dot);

  if extension == {
    case ".css";  return "text/css";
    case ".js";   return "text/javascript";
    case ".mps";  return "audio/mpeg";
    case ".png";  return "image/png";
    case ".webm"; return "video/webm";
    case ".webp"; return "image/webp";
    case ".gif";  return "image/gif";
    case ".ico";  return "image/x-icon";
    case ".jpg";  return "image/jpeg";
    case ".jpeg"; return "image/jpeg";
    case ".svg";  return "image/svg+xml";
    case ".ini";  return "text/plain";
    case ".txt";  return "text/plain";
    case ".exe";  return "application/octet-stream";
  }

  return "text/html";
}


normalize_path :: (path: string) -> string { return trim(path, "/"); }

normalize_filename :: (raw_filename: string) -> string {
  filename := raw_filename;

  { // strip questionmark from filename if it exists ex: main.js?293849203
    questionmark_location_in_filename := find_index_from_left(filename, #char "?");
    if questionmark_location_in_filename != -1 {
      filename.count = questionmark_location_in_filename;
    }
  }

  { // replace %xx with xx conveted to a hex byte
    start_index := 0;
    while true {
      percent_location_in_filename := find_index_from_left(filename, #char "%", start_index);
      percent_escape_exists := percent_location_in_filename != -1;
      if !percent_escape_exists break;
      // todo check that there's actually 2 hex chars after the percent
      // ^ this probably can currently crash the server
      // todo make sure it's valid hex? not sure how this should be handled if it's not? probably just ignored?
      hex_chars := substr(filename, percent_location_in_filename + 1, 2);
      string_byte := hex_chars_to_byte(hex_chars);

      filename.data[percent_location_in_filename] = string_byte;
      copy_starting_from := percent_location_in_filename + 1 + 2;
      memcpy(filename.data + percent_location_in_filename + 1, filename.data + copy_starting_from, filename.count-copy_starting_from);
      filename.count -= 2;

      start_index = percent_location_in_filename + 1;
    }
  }

  return filename;
}

hex_char_to_int :: (char: u8) -> u8 {
  if char >= #char "a" return (char - #char "a" + 0xA);
  if char >= #char "A" return (char - #char "A" + 0xA);
  if char >= #char "0" return (char - #char "0");
  return 1;
}
hex_chars_to_byte :: (chars: string) -> u8 {
  assert(chars.count == 2);
  return hex_char_to_int(chars[0]) * 16 + hex_char_to_int(chars[1]);
}





mysocket_close :: socket_close;

mysocket_read :: (socket: Socket, buffer: *u8, bufferlen: s32) -> s64
{
  #if OS == .LINUX
    if ssl_is_socket_ssl(socket) // perf hash table lookup
      return ssl_read(socket, buffer, xx bufferlen);

  return recv(socket, buffer, xx bufferlen, 0);
}

mysocket_write :: (socket: *Socket, buffer: string) -> bool
{
    bytes := buffer.count;
    sent := 0;
    while sent < bytes
    {
        result := mysocket_send(<<socket, buffer);
        if result < 0
        {
            err := errno();
            if err == {
              case EPIPE; // even with this EPIPE check, signal(SIGPIPE, SIG_IGN) still seems necessary to stop the program from crashing on SIGPIPE
                log("Client disconnected or connection closed");
                mysocket_close(socket);
              case;
                log("Error writing to socket: %", err);
            }
            return false;
        }
        sent += result;
    }
    return true;
}

mysocket_send :: (socket: Socket, buffer: string) -> s64 {
    if ssl_is_socket_ssl(socket) // perf hash table lookup
      return ssl_write(socket, buffer.data, xx buffer.count);

  return send(socket, buffer.data, xx buffer.count, 0);
}



#import "String";
