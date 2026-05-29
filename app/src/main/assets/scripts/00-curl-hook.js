// Hook to transparently map 'curl' subprocess calls to Java execution on Android
var files_dir = mp.utils.getenv("MPVRX_FILES_DIR");

if (files_dir) {
    function basename(path) {
        return String(path || "").replace(/\\/g, "/").split("/").pop();
    }

    function is_curl_command(args) {
        return args && args.length > 0 && basename(args[0]) === "curl";
    }

    var old_command_native = mp.command_native;
    mp.command_native = function(table, def) {
        if (table && table.name === "subprocess" && is_curl_command(table.args)) {
            var req_id = String(Date.now()) + "_" + String(Math.floor(Math.random() * 900000) + 100000);
            var req_path = files_dir + "/curl_req_" + req_id + ".json";
            var res_path = files_dir + "/curl_res_" + req_id + ".json";

            var req_payload = JSON.stringify({ args: table.args });

            var write_ok = mp.utils.write_file("file://" + req_path, req_payload);
            if (!write_ok) {
                return {
                    status: -1,
                    stdout: "",
                    stderr: "Failed to write request JSON inside JS hook",
                    error_string: "init"
                };
            }

            mp.set_property("user-data/mpvrx/run_curl", req_id);

            var res_payload = null;
            var start_time = mp.get_time();
            var timeout = 60.0;
            while (true) {
                var t = mp.get_time() + 0.02;
                while (mp.get_time() < t) {}

                res_payload = mp.utils.read_file("file://" + res_path);
                if (res_payload !== undefined && res_payload !== null) {
                    break;
                }
                if (mp.get_time() - start_time > timeout) {
                    break;
                }
            }

            if (res_payload === undefined || res_payload === null) {
                return {
                    status: -1,
                    stdout: "",
                    stderr: "Curl subprocess timeout/failed",
                    error_string: "timeout"
                };
            }

            try {
                var res_table = JSON.parse(res_payload);
                return res_table;
            } catch (e) {
                return {
                    status: -1,
                    stdout: "",
                    stderr: "Failed to parse response JSON: " + res_payload,
                    error_string: "parse"
                };
            }
        }
        return old_command_native(table, def);
    };
}
