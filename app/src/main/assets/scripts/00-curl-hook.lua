-- Hook to transparently map 'curl' subprocess calls to Java execution on Android
local files_dir = os.getenv("MPVRX_FILES_DIR")
local utils = require "mp.utils"

if files_dir then
    local function basename(path)
        return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or ""
    end

    local function is_curl_command(args)
        return type(args) == "table" and basename(args[1]) == "curl"
    end

    local old_command_native = mp.command_native
    mp.command_native = function(table, def)
        if type(table) == "table" and table.name == "subprocess" and is_curl_command(table.args) then
            local req_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
            local req_path = files_dir .. "/curl_req_" .. req_id .. ".json"
            local res_path = files_dir .. "/curl_res_" .. req_id .. ".json"

            local req_payload = utils.format_json({ args = table.args })
            
            local req_file = io.open(req_path, "w")
            if req_file then
                req_file:write(req_payload)
                req_file:close()
            else
                return {
                    status = -1,
                    stdout = "",
                    stderr = "Failed to write request JSON inside Lua hook",
                    error_string = "init"
                }
            end

            mp.set_property("user-data/mpvrx/run_curl", req_id)

            local res_file = nil
            local start_time = mp.get_time()
            local timeout = 60.0
            while not res_file do
                local t = mp.get_time() + 0.02
                while mp.get_time() < t do end

                res_file = io.open(res_path, "r")
                if mp.get_time() - start_time > timeout then
                    break
                end
            end

            if not res_file then
                os.remove(req_path)
                return {
                    status = -1,
                    stdout = "",
                    stderr = "Curl subprocess timeout/failed",
                    error_string = "timeout"
                }
            end

            local res_payload = res_file:read("*all")
            res_file:close()

            os.remove(req_path)
            os.remove(res_path)

            local ok, res_table = pcall(utils.parse_json, res_payload)
            if ok and type(res_table) == "table" then
                return res_table
            else
                return {
                    status = -1,
                    stdout = "",
                    stderr = "Failed to parse response JSON: " .. tostring(res_payload),
                    error_string = "parse"
                }
            end
        end
        return old_command_native(table, def)
    end
end
