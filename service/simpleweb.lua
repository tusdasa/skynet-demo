local skynet = require "skynet"
local socket = require "skynet.socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
--local json = require "json"
local cjson = require "cjson"
local staticfile = require "staticfile"

local table = table
local string = string

local handler
local mode = ...

if mode == "agent" then

local function response(fd, ...)
    local ok, err = httpd.write_response(sockethelper.writefunc(fd), ...)
    if not ok then
        -- if err == sockethelper.socket_error , that means socket closed.
        if err ~= sockethelper.socket_error then
            skynet.error(string.format("fd = %d, %s", fd, err))
        end
    end
end

skynet.start(function()
	handler = assert(skynet.uniqueservice "handler")
	skynet.dispatch("lua", function (_, _, fd)
    socket.start(fd)
	-- limit 8M
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(fd))
        if body and body ~= "" then
	   --Content-Type
	   if(header["Content-Type"] == "application/json") then
        local tmp = cjson.decode(body)
        body = nil
		body = tmp
	   end
    end
	if code then
	    -- 特殊请求判断
            if code ~= 200 then
                response(fd, code)
            else
                local action, query = urllib.parse(url)
                skynet.error("action:"..action)
                local query_table = {}
                if query then
                    query_table = urllib.parse_query(query)
                end
                    local http_method = method:lower()
                    --TODO 前缀树算法实现路由匹配
                    local router_path = action:sub(2)
                    print("router_path: "..router_path)
                    -- 拼接访问的方法
                    local func_name = string.format("%s_%s", http_method, router_path)
                    local ret, c = skynet.call(handler, "lua", func_name, query_table, header, body)
                if type(ret) ~= "string" then
                    ret = cjson.encode(ret or {})
                end
                    c = c or 200
                    header = {}
                    header["Content-Type"] = "application/json"
                    response(fd, c, ret, header)
            end
        else
            if url == sockethelper.socket_error then
                skynet.error("socket closed")
            else
                skynet.error(url)
            end
        end
        socket.close(fd)
    end)
end)

else

skynet.start(function()
    local agent = {}
    for i= 1, 20 do
        agent[i] = skynet.newservice(SERVICE_NAME, "agent")
    end

    local http_port = skynet.getenv("http_port")
    local balance = 1
    local fd = socket.listen("0.0.0.0", http_port)
    skynet.error("Listen web port:", http_port)
    socket.start(fd , function(fd, addr)
        -- skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
        skynet.send(agent[balance], "lua", fd)
        balance = balance + 1
        if balance > #agent then
            balance = 1
        end
    end)
end)

end
