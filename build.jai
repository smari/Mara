#import "Basic";
#import "Compiler";
#import "String";

#run {
    set_build_options_dc(.{do_output=false});

    w := compiler_create_workspace("Mara build");
    if !w {
        print("Error: Could not create a workspace\n");
        exit(1);
    }

    set_working_directory(#filepath);
    build_options := get_build_options(w);
    imports : [..]string;
    for build_options.import_path array_add(*imports, it);
    array_add(*imports, "lib/");
    build_options.import_path = imports;

    debug := true;
    args := build_options.compile_time_command_line;

    for arg, index : args {
        print("    [%] '%'\n", index, arg);

        if arg == {
            case "debug";
              // ...

            case "release";
              debug = false;

            case;
              print("Error: Unsupported argument: '%'\n", arg);
              exit(1);
        }
    }

    mode : string;

    if debug {
        mode = "DEBUG :: true;";
    } else {
        mode = "DEBUG :: false;";
    }

    if !w {
        print("[build.jai] 'compiler_create_workspace' failed\n");
        exit(1);
    }

    build_options.output_type = .EXECUTABLE;
    build_options.output_executable_name = "mara";
    build_options.output_path = "";
    set_build_options(build_options, w);

    compiler_begin_intercept(w);

    add_build_file("src/main.jai", w);
    add_build_string(mode, w);

    while true {
        message := compiler_wait_for_message();

        if !message {
            continue;
        }

        if message.kind == .COMPLETE {
            break;
        }
    }

    compiler_end_intercept(w);
};
