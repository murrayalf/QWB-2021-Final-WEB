local http = require "resty.http"
local resolver = require "resty.dns.resolver"

local _M = {}

_M._VERSION="0.1"

function _M:http_request_with_dns( url, param )
    -- get domain
    local domain = ngx.re.match(url, [[//([\S]+?)/]])
    domain = (domain and 1 == #domain and domain[1]) or nil
    if not domain then
        ngx.log(ngx.ERR, "get the domain fail from url:", url)
        return {status=ngx.HTTP_BAD_REQUEST}
    end

    -- add param
    if not param.headers then
        param.headers = {}
    end
    param.headers.Host = domain

    -- get domain ip
    local domain_ip, err = self:get_domain_ip_by_dns(domain)
    if not domain_ip then
        ngx.log(ngx.ERR, "get the domain[", domain ,"] ip by dns failed:", err)
        return {status=ngx.HTTP_SERVICE_UNAVAILABLE}
    end

    -- http request
    local httpc = http.new()
    local temp_url = ngx.re.gsub(url, "//"..domain.."/", string.format("//%s/", domain_ip))

    local res, err = httpc:request_uri(temp_url, param)
    if err then
        return {status=ngx.HTTP_SERVICE_UNAVAILABLE}
    end

    -- httpc:request_uri 内部已经调用了keepalive，默认支持长连接
    -- httpc:set_keepalive(1000, 100)
    return res
end


-- 根据域名获取IP地址
function _M:get_domain_ip_by_dns( domain )
  -- 这里写死了google的域名服务ip，要根据实际情况做调整（例如放到指定配置或数据库中）
  local dns = "8.8.8.8"

  local r, err = resolver:new{
      nameservers = {dns, {dns, 53} },
      retrans = 5,  -- 5 retransmissions on receive timeout
      timeout = 2000,  -- 2 sec
  }

  if not r then
      return nil, "failed to instantiate the resolver: " .. err
  end

  local answers, err = r:query(domain)
  if not answers then
      return nil, "failed to query the DNS server: " .. err
  end

  if answers.errcode then
      return nil, "server returned error code: " .. answers.errcode .. ": " .. answers.errstr
  end

  for i, ans in ipairs(answers) do
    if ans.address then
      return ans.address
    end
  end

  return nil, "not founded"
end

return _M