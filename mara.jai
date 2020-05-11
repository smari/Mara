// Mara: A Gopher Server.
#import "Basic";
#import "POSIX";
#import "Process";
#import "Socket";
#import "String";
#import "File";
#import "File_Utilities";
#import "Sort";

SERVER_NAME     :: "Mara";
SERVER_VERSION  :: "0.0.1";
SERVER_NUM_CONNECTIONS :: 5;

TRIM_CHARS      :: " \t\r\n";
PASSWD_MIN_UID  :: 100;
BUF_MAX :: 1000;

TYPE_TEXT   :: "0";
TYPE_MENU   :: "1";
TYPE_ERROR  :: "3";
TYPE_MACBIN :: "4";
TYPE_GZIP   :: "5";
TYPE_QUERY  :: "7";
TYPE_BINARY :: "9";
TYPE_GIF    :: "g";
TYPE_HTML   :: "h";
TYPE_INFO   :: "i";
TYPE_IMAGE  :: "I";
TYPE_MIME   :: "M";
TYPE_DOC    :: "d";
TYPE_SOUND  :: "s";
TYPE_VIDEO  :: ";";
TYPE_TITLE  :: "!";

GopherProtocol :: enum {
    PROTO_GOPHER;
    PROTO_HTTP;
}

GopherServer :: struct {
    stat_requests:       int;
    stat_bytes_sent:     int;
    stat_bytes_received: int;
    stat_files_served:   int;
    stat_maps_served:    int;

    req_selector:        string;
    req_realpath:        string;
    req_query_string:    string;
    req_search:          string;
    req_referrer:        string;
    req_local_addr:      string;
    req_remote_addr:     string;
    req_filetype:        string;
    req_filesize:        int;
    req_protocol:        GopherProtocol;

    client_socket:       s32;

    out_width:           int    = 67;
    out_charset:         string = "utf-8";

    server_description:  string = "";
    server_location:     string = "";
    server_platform:     string = "Linux";
    server_admin:        string = "";
    server_root:         string = "gopherroot/";
    server_host:         string;
    server_listen:       string = "0.0.0.0";
    server_port:         u16    = 70;

    session_timeout:     int    = 1600;

    default_filetype:    string = TYPE_TEXT;
    map_file:            string = "gophermap";
    tag_file:            string = "gophertag";
    user_dir:            string = "public_gopher";

    opt_parent:          bool   = false; // Unimplemented
    opt_header:          bool   = false; // Unimplemented
    opt_footer:          bool   = false; // Unimplemented
    opt_date:            bool   = false; // Unimplemented
    opt_syslog:          bool   = false; // Unimplemented
    opt_magic:           bool   = true;
    opt_iconv:           bool   = false; // Unimplemented
    opt_vhost:           bool   = false; // Unimplemented
    opt_query:           bool   = false; // Unimplemented
    opt_caps:            bool   = true;
    opt_status:          bool   = false; // Unimplemented
    opt_stats:           bool   = true;
    opt_shm:             bool   = false; // Unimplemented
    opt_root:            bool   = true;
    opt_proxy:           bool   = false; // Unimplemented
    opt_exec:            bool   = false;
    opt_personal_spaces: bool   = true;
    opt_http_requests:   bool   = true;
    debug:               bool   = true;
};

server : GopherServer;

write :: (fd: s32, buf: string, args: ..Any) -> s64 {
    tmp := tprint(buf, ..args);
    return write(fd, tmp.data, xx tmp.count);
}

write :: (fd: s32, buf: string) -> s64 {
    return write(fd, buf.data, xx buf.count);
}

read_line :: (fd: s32) -> string {
    buf : string;
    buf.data = alloc(BUF_MAX);
    buf.count = BUF_MAX;
    view := buf;
    while true {
        read(fd, *view.data, 1);
        buf.count = (view.data-buf.data);
        if buf.count >= BUF_MAX return buf;
        if view.data[0] == #char "\n" return buf;
    }
    return buf;
}

notice :: (msg: string, args: ..Any) {
    if server.debug {
        msgst := tprint(msg, ..args);
        print("[Notice ] %\n", msgst);
    }
}

warning :: (msg: string, args: ..Any) {
    msgst := tprint(msg, ..args);
    print("[Warning] %\n", msgst);
}

error :: (msg: string, args: ..Any) {
    errst := tprint(msg, ..args);
    print("[Error  ] %\n", errst);
    exit(1);
}

get_error :: () -> string {
    err := errno();
    if err == {
        case EPERM; return "Operation not permitted";
        case ENOENT; return "No such file or directory";
        case ENOMEM; return "Out of memory";
        case; return tprint("%", err);
    }
}

User :: struct {
    username:   string;
    mtime:      s64;
}

send_userlist :: (using server: *GopherServer) {
    if !opt_personal_spaces return;

    setpwent();
    users : [..]User;
    dir: stat_t;

    while true {
        pwd := getpwent();
        if !pwd break;
		/* Skip too small uids */
		if pwd.pw_uid < PASSWD_MIN_UID continue;

		/* Look for a world-readable user-owned ~/public_gopher */
		temp := tprint("%/%", to_string(pwd.pw_dir), user_dir);
		if stat(temp_c_string(temp), *dir) != 0 continue;
		if dir.st_mode & S_IROTH == 0 continue;
		if dir.st_uid != pwd.pw_uid continue;

		/* Found one */
        user : User;
        user.username = copy_string(to_string(pwd.pw_name));
        user.mtime = dir.st_mtime.tv_sec;
        array_add(*users, user);
	}
    if opt_date quick_sort(users, a => a.mtime);
    else quick_sort(users, (a, b) => compare_strings(a.username, b.username));

    notice("A total of % users have % directories.", users.count, user_dir);
    for user:users {
        send_line(server, tprint("%", user.username), TYPE_MENU, tprint("/~%/", user.username));
    }
    array_reset(*users);
}

send_line :: (using server: *GopherServer, line: string, _type: string = "", _selector: string = "") {
    selector := _selector; type := _type;
    if type == TYPE_TITLE { selector = "TITLE"; type = TYPE_INFO; }
    assert(type.count <= 1);
    server.stat_bytes_sent += write(server.client_socket, "%1%2\t%3\t%4\t%5\r\n", type, line, selector, server_host, server_port);
}

send_error :: (using server: *GopherServer, errormsg: string = "Unknown error") {
    server.stat_bytes_sent += write(client_socket, "3%\tTITLE\t%\t%\r\n", errormsg, server_host, server_port);
}

send_exec_gophermap :: (server: *GopherServer, gophermap: string, depth := 0) {
    /*
    lines: [..]string;
    print("Doing the = fun!\n");
    fp := popen(temp_c_string(gophermap), temp_c_string("r"));
    while true {
        line := read_line(xx fp);
        if !line break;
        array_add(*lines, line);
        break;
    }
    pclose(fp);
    */
    warning("Executable gophermaps don't work yet.");
}

send_gophermap :: (server: *GopherServer, gophermap: string, depth := 0) {
    if depth > 10 return;
    lines: []string;

    if !file_exists(gophermap) {
        if server.opt_exec {
            send_exec_gophermap(server, gophermap, depth+1);
        } else {
            warning("Could not serve index: file not found.");
            send_error(server, "Index not found.");
            return;
        }
    }

    stats: stat_t;
    ret := stat(temp_c_string(server.req_realpath), *stats);
    if stats.st_mode & S_IXOTH && server.opt_exec {
        // Our gophermap is an executable!
        error("No support for executable gophermaps yet.");
    }

    buf, success := read_entire_file(gophermap);
    notice("Client requested index. Reading from %", gophermap);

    defer free(buf);
    if !success {
        notice("Error reading file %: %", gophermap, get_error());
        send_error(server, "Internal error.");
        return;
    }
    lines = split(buf, "\n");
    defer array_reset(*lines);

    server.stat_maps_served += 1;
    for line:lines {
        trim(line, TRIM_CHARS);
        if line.count == 0 continue;
        type := line; type.count = 1;
        name := line; advance(*name);
        if type == {
            case "#"; continue;
            case "*"; return;
            case "."; return;
            case "~"; send_userlist(server); continue;
            case "="; {
                send_gophermap(server, name, depth+1);
                continue;
            }
            case TYPE_TITLE; send_line(server, name, type);
            case; {
                host: string;
                port: u16;
                parts := split(name, "\t");
                defer array_reset(*parts);
                if parts.count < 2 { send_line(server, name, TYPE_INFO); continue; }
                name = parts[0];
                selector := parts[1];

                if parts.count > 2  host = parts[2];
                else                host = server.server_host;

                if parts.count > 3  port = parse_int(*parts[3], u16);
                else                port = server.server_port;

                if begins_with(selector, "/") || host != server.server_host || begins_with(selector, "URL:") {
                    server.stat_bytes_sent += write(server.client_socket, "%1%2\t%3\t%4\t%5\r\n", type, name, selector, host, port);
                } else { // Relative resource:
                    selector = trim_left(selector, "/");
                    server.stat_bytes_sent += write(server.client_socket, "%1%2\t%3/%4\t%5\t%6\r\n", type, name, server.req_selector, selector, host, port);
                }
            }
        }
    }
}

send_file :: (server: *GopherServer) {
    file_name := find_character_from_right(server.req_realpath, #char "/");
    if file_name.count == 0 {
        send_error(server, "Bad request.");
        return;
    }
    advance(*file_name);
    if file_name == server.map_file || file_name == server.tag_file {
        send_error(server, "Permission denied.");
        return;
    }
    // TODO: Do we want to apply further filters? (e.g. for security?)
    buf, success := read_entire_file(server.req_realpath);
    defer free(buf);
    if !success {
        notice("Error reading file %: %", server.req_realpath, get_error());
        send_error(server, "File not found.");
        return;
    }
    server.stat_bytes_sent += write(server.client_socket, buf);
    server.stat_files_served += 1;
}

send_caps :: (using server: *GopherServer) {
    wt :: (str: string, args: ..Any) #expand {
        `stat_bytes_sent += write(`client_socket, str, ..args);
    }
    wt("CAPS\r\n\r\n");
    wt("##\r\n");
    wt("## This is an automatically generated caps file.\r\n");
    wt("##\r\n");
    wt("\r\n");
    wt("CapsVersion=1\r\n");
    wt("ExpireCapsAfter=%\r\n", session_timeout);
    wt("\r\n");
    wt("PathDelimeter=/\r\n");
    wt("PathIdentity=.\r\n");
    wt("PathParent=..\r\n");
    wt("PathParentDouble=FALSE\r\n");
    wt("PathKeepPreDelimeter=FALSE\r\n");
    wt("ServerSupportsStdinScripts=TRUE\r\n");
    wt("ServerDefaultEncoding=%\r\n", out_charset);
    wt("\r\n");
    wt("ServerSoftware=%\r\n", SERVER_NAME);
    wt("ServerSoftwareVersion=%\r\n", SERVER_VERSION);
    wt("ServerArchitecture=%\r\n", server_platform);
	/* Optional keys */
	if server_description wt("ServerDescription=%\r\n", server_description);
	if server_location wt("ServerGeolocationString=%\r\n", server_location);
	if server_admin wt("ServerAdmin=%\r\n", server_admin);
}

send_stats :: (using server: *GopherServer) {
    send_line(server, "i    /\\/\\   __ _ _ __ __ _ ");
    send_line(server, "i   /    \\ / _` | '__/ _` |");
    send_line(server, "i  / /\\/\\ \\ (_| | | | (_| |");
    send_line(server, "i  \\/    \\/\\__,_|_|  \\__,_|");
    send_line(server, tprint("i % Gopher Server v%", SERVER_NAME, SERVER_VERSION));
    send_line(server, "i  ");
    send_line(server, "i  ");
    send_line(server, tprint("iRequests handled: %", stat_requests));
    send_line(server, tprint("iBytes sent      : %", stat_bytes_sent));
    send_line(server, tprint("iBytes received  : %", stat_bytes_received));
    send_line(server, tprint("iMaps sent       : %", stat_maps_served));
    send_line(server, tprint("iFiles sent      : %", stat_files_served));
}

guess_filetype :: (using server: *GopherServer) -> string {
    find_in_end :: (returns: string, needles: []string) #expand {
        for n:needles { if ends_with(`req_selector, n) return returns; }
    }
    // Check if menu:
    if ends_with(req_selector, "/") { return TYPE_MENU; }
    stats: stat_t;
    ret := stat(temp_c_string(req_realpath), *stats);
    if S_ISDIR(stats.st_mode) { return TYPE_MENU; }
    // Check other types:
    find_in_end(TYPE_TEXT, {:string: "txt", "jai", "pl", "py", "sh", "tcl", "c", "cpp", "h", "log", "conf", "php", "php3"});
    find_in_end(TYPE_MENU, {:string: "map", "menu"});
    find_in_end(TYPE_MACBIN, {:string: "hqx"});
    find_in_end(TYPE_GZIP, {:string: "Z", "gz", "tgz", "tar", "zip", "bz2", "rar", "sea"});
    find_in_end(TYPE_QUERY, {:string: "q", "qry"});
    find_in_end(TYPE_BINARY, {:string: "iso", "so", "o", "rtf", "ttf", "bin", "exe"});
    find_in_end(TYPE_GIF, {:string: "gif"});
    find_in_end(TYPE_HTML, {:string: "html", "htm", "xhtml", "css", "rss", "xml", "rdf"});
    find_in_end(TYPE_IMAGE, {:string: "jpg", "jpeg", "png", "bmp", "svg", "tif", "tiff", "ico", "xbm", "xpm", "pcx"});
    find_in_end(TYPE_MIME, {:string: "mbox"});
    find_in_end(TYPE_DOC, {:string: "pdf", "ps", "doc", "ppt", "xls", "xlsx", "docx", "pptx", "ods", "odp", "odt"});
    find_in_end(TYPE_SOUND, {:string: "mp3", "wav", "wma", "flac", "ogg", "aiff", "aac"});
    find_in_end(TYPE_VIDEO, {:string: "avi", "mp4", "mpg", "mov", "qt", "ogv", "webm", "m4v", "mpv"});
    notice("Not sure what % is.", req_selector);
    return default_filetype;
}

url_redirect :: (using server: *GopherServer) {
    if !begins_with(req_selector, "http://") &&
       !begins_with(req_selector, "https://") &&
       !begins_with(req_selector, "ftp://") &&
       !begins_with(req_selector, "mailto://") &&
       !begins_with(req_selector, "irc://") {
        send_error(server, "Unknown protocol on HTTP redirect.");
        return;
    }
    wt :: (str: string, args: ..Any) #expand {
        `stat_bytes_sent += write(`client_socket, str, ..args);
    }

	wt("<html>\n<head>\n");
	wt("  <meta http-equiv=\"Refresh\" content=\"1;URL=%\">\n", req_selector);
	wt("  <meta http-equiv=\"Content-Type\" content=\"text/html;charset=iso-8859-1\">\n");
	wt("  <title>Redirecting</title>\n");
	wt("</head>\n<body>\n");
	wt("  <h1>Redirecting</h1>\n");
    wt("  Redirecting to <a href=\"%\">%</a>.\n", req_selector, req_selector);
	wt("</body>\n</html>\n");
}

handle_request :: (using server: *GopherServer) {
    if opt_caps && req_selector == "/caps.txt" {
        send_caps(server);
        return;
    }

    if opt_stats && req_selector == "/server_stats" {
        send_stats(server);
        return;
    }

    if begins_with(req_selector, "URL:") {
        req_filetype = TYPE_HTML;
        req_selector.data += 4; // Fast forward over "URL:"
        url_redirect(server);
        return;
    }

    if opt_http_requests && (begins_with(req_selector, "GET ") || begins_with(req_selector, "POST ")) {
        req_protocol = .PROTO_HTTP;
        // TODO: When lots of things break, it'll be because this API became sane:
        req_selector = find_character_from_left_v2(req_selector, #char " ");
        req_selector = find_character_from_left(req_selector, #char " ");
        notice("Got HTTP request.");
    }

    notice("Client requested '%'", req_selector);
    if opt_personal_spaces && user_dir != "" && begins_with(req_selector, "/~") {
        // Map ~user to $HOME/public_gopher
        path := req_selector;
        advance(*path, 2);
        username := find_character_from_left(path, #char "/");
        path = find_character_from_left_v2(path, #char "/");
        pwd := getpwnam(temp_c_string(username));
        // Unlike Gophernicus, we won't leak info on user existence.
        if !pwd || pwd.pw_uid < PASSWD_MIN_UID { send_error(server, "File not found"); return; }

        req_realpath = join(to_string(pwd.pw_dir), "/", user_dir, path);
        notice("Resolving % to %", req_selector, req_realpath);
    } else {
        req_realpath = join(server_root, req_selector);
    }

    req_filetype = guess_filetype(server);

    if !file_exists(req_realpath) { send_error(server, "File not found"); return; }
    if req_filetype == {
        case TYPE_MENU;
            gophermap := join(server.req_realpath, "/", server.map_file);
            send_gophermap(server, gophermap);
            free(gophermap);
        case; send_file(server);
    }
}

new_client :: (using server: *GopherServer) {
    req_protocol = .PROTO_GOPHER;
}

start_server :: (using server: *GopherServer) {
    server_root = trim_right(server_root, "/");
    defer free(server_root);
    server_socket := socket(AF_INET, SOCK_STREAM, 0);
    if server_socket < 0 error("Couldn't open socket!");

    optval := 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, *optval, size_of(socklen_t));

    if bind(server_socket, server_listen, server_port) < 0 {
        err := errno();
        if err == {
            case EACCES; error("Attempting to listen on %:% without superuser privileges.", server_listen, server_port);
            case EADDRINUSE; error("Address in use: %:%.", server_listen, server_port);
            case; error("Unknown error % when binding.", err);
        }
    }

    if listen(server_socket, SERVER_NUM_CONNECTIONS) < 0 error("Error listening.");
    defer close(server_socket);

    notice("Server running on %:%.", server.server_listen, server.server_port);

    while true {
        new_client(server);
        client_socket, address := accept(server_socket);
        server.client_socket = client_socket;
        notice("Client connected from %", to_string(address));

        request : [BUF_MAX]u8;
        server.stat_bytes_received += read(client_socket, *request, BUF_MAX);
        server.req_selector = trim(to_string(request), TRIM_CHARS);
        server.stat_requests += 1;
        handle_request(server);

        close(server.client_socket);
    }
}

version :: () {
    print("% %\n", SERVER_NAME, SERVER_VERSION);
}

main :: () {
    idx := 1;
    args := get_command_line_arguments();
    defer array_reset(*args);
    tmp : string;

    get_param :: (args: []string, idx: int) -> int, string {
        if idx+1 >= args.count { error("Parameters missing."); }
        return idx+1, args[idx+1];
    }

    while idx < args.count {
        if args[idx] == {
            case "-v"; version(); exit(0);
            case "-h"; idx, server.server_host = get_param(args, idx);
            case "-p"; idx, tmp = get_param(args, idx); server.server_port = parse_int(*tmp, u16);
            case "-r"; idx, server.server_root = get_param(args, idx);
            case "-nr"; server.opt_root = false;
            case "-nc"; server.opt_magic = false;
            case "-na"; server.opt_caps = false;
            case "-nx"; server.opt_exec = false;
            case "-nu"; server.opt_personal_spaces = false;
            case "-nS"; server.opt_stats = false;
            case "-d"; server.debug = true;
            case; print("Unknown parameter %", args[idx]);
        }
        idx += 1;
    }

    if !file_exists(server.server_root) { error("Server root % does not exist.", server.server_root); }
    if server.opt_root && getuid() == 0 { error("Refusing to run as root."); }
    notice("Serving from %", server.server_root);

    start_server(*server);
}
