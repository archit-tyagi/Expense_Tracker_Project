local kong = kong
local http = require "resty.http"

local CustomAuthHandler = {
  PRIORITY = 1000,
  VERSION = "1.1",
}

function CustomAuthHandler:access(config)
  -- Use the auth_service_url from the configuration
  local auth_service_url = config.auth_service_url

  -- Call auth service
  local httpc = http.new()
  httpc:set_timeouts(10000, 10000, 10000)
  local res, err = httpc:request_uri(auth_service_url, {
    method = "GET",
    headers = {
      ["Authorization"] = kong.request.get_header("Authorization")
    }
  })

  if not res then
    kong.log.err("Failed to call auth service: ", err)
    return kong.response.exit(500, { message = "Internal Server Error" })
  end

  if res.status ~= 200 then
    return kong.response.exit(res.status, { message = "Unauthorized" })
  end

  -- If authenticated, add user_id to headers and continue
  local user_id = res.body -- Assuming auth service returns user_id in body
  kong.service.request.set_header("X-User-ID", user_id)

  -- If the access token was expired, the auth service mints a new one and returns it
  -- in the /ping response's Authorization header. Upstream services do not need it
  -- (they are authorized solely by the /ping check), so only stash it here and hand it
  -- back to the client in header_filter.
  local new_token = res.headers["Authorization"]
  if new_token then
    kong.ctx.plugin.new_access_token = new_token
  end
end

function CustomAuthHandler:header_filter(config)
  local new_token = kong.ctx.plugin.new_access_token
  if new_token then
    -- Return the refreshed access token to the client on the response.
    kong.response.set_header("Authorization", new_token)
    -- Allow browser JS clients to read the header across origins.
    kong.response.set_header("Access-Control-Expose-Headers", "Authorization")
  end
end

return CustomAuthHandler