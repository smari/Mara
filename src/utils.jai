// Smári's standalone Jai utilities, r1
// Hypothetically most of this belongs in the standard library
//  or at least some easily available module.

// File/socket tools:

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


// Error/warning/notice printing
// TODO: Add syslog support.
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

// errno() stringification utility function.
get_error :: () -> string {
    err := errno();
    if err == {
        case EPERM; return "Operation not permitted";
        case ENOENT; return "No such file or directory";
        case ENOMEM; return "Out of memory";
        case; return tprint("%", err);
    }
}
