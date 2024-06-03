cd /tmp

eval `luarocks path`

cat <<EOF > script.lua

local function dump(o)
  if type(o) == 'table' then
     local s = '{ '
     for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. dump(v) .. ','
     end
     return s .. '} '
  else
     return tostring(o)
  end
end

local options = {}
local resolvconffile = options.resolvConf or "/etc/resolv.conf"
local utils = require("kong.resty.dns.utils")
local fileexists = require("pl.path").exists

if ((type(resolvconffile) == "string") and (fileexists(resolvconffile)) or
    (type(resolvconffile) == "table")) then
  resolv, err = utils.applyEnv(utils.parseResolvConf(resolvconffile))
  if not resolv then return resolv, err end
else
  log(WARN, PREFIX, "Resolv.conf file not found: "..tostring(resolvconffile))
  resolv = {}
end
if not resolv.options then resolv.options = {} end

if #(options.nameservers or {}) == 0 and resolv.nameserver then
  options.nameservers = {}
  -- some systems support port numbers in nameserver entries, so must parse those
  for _, address in ipairs(resolv.nameserver) do
    local ip, port, t = utils.parseHostname(address)
    if t == "ipv6" and not options.enable_ipv6 then
      -- should not add this one
      log(DEBUG, PREFIX, "skipping IPv6 nameserver ", port and (ip..":"..port) or ip)
    elseif t == "ipv6" and ip:find([[%]], nil, true) then
      -- ipv6 with a scope
      log(DEBUG, PREFIX, "skipping IPv6 nameserver (scope not supported) ", port and (ip..":"..port) or ip)
    else
      if port then
        options.nameservers[#options.nameservers + 1] = { ip, port }
      else
        options.nameservers[#options.nameservers + 1] = ip
      end
    end
  end
end

local resolver = require "resty.dns.resolver"
local r, err = resolver:new{
    nameservers = options.nameservers,
    retrans = 1,  -- 5 retransmissions on receive timeout
    timeout = 2000,  -- 2 sec
    no_random = false, -- always start with first nameserver
}

if not r then
    ngx.say("failed to instantiate the resolver: ", err)
    return
end

local answers, err, tries = r:query(

  "google.com",                   -- <---- PUT THE ADDRESS TO TEST HERE -- --

  { qtype = r.TYPE_A }, {})
if not answers then
    ngx.say("failed to query the DNS server: ", err)
    ngx.say("retry history:\n  ", table.concat(tries, "\n  "))
    return
end

if answers.errcode then
    ngx.say("server returned error code: ", answers.errcode,
            ": ", answers.errstr)
end

for i, ans in ipairs(answers) do
    print ('')
    print('*****************************************************')
    print('**')
    print('** TRYING: ' .. ans.address .. '                         **')
    print('**')
    print('*****************************************************')

    -- NOW CALL EACH ONE
    local http = require "resty.http"
    local httpc = http.new()

    local res, err = httpc:request_uri("http://" .. ans.address .. ":9081/", {
      method = "GET",
      headers = {
          ["Host"] = "google.com",    -- <---- SAME ADDRESS HERE -- --
      },
      ssl_verify = false,
    })
    if not res then
      ngx.log(ngx.ERR, "request failed: ", err)
      return
    end

    -- At this point, the entire request / response is complete and the connection
    -- will be closed or back on the connection pool.

    -- The `res` table contains the expeected `status`, `headers` and `body` fields.
    print(dump(res))
end

EOF

resty --errlog-level=debug script.lua
