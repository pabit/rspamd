--[[
Copyright (c) 2016, Andrew Lewis <nerf@judo.za.org>
Copyright (c) 2016, Vsevolod Stakhov <vsevolod@highsecure.ru>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]--

-- A plugin that pushes metadata (or whole messages) to external services

local rspamd_logger = require "rspamd_logger"

local settings = {
  select = function(task)
    return true
  end,
  format = function(task)
    return task:get_content()
  end,
}

local opts = rspamd_config:get_all_opt('metadata_exporter')
if not opts then return end
local redis_params = rspamd_parse_redis_server('metadata_exporter')
if not redis_params then
  rspamd_logger.errx(rspamd_config, 'no servers are specified, disabling module')
  return
end
local channel = opts['channel']
if not channel then
  rspamd_logger.errx(rspamd_config, 'no channel is specified, disabling module')
  return
end
if opts['select'] then
  settings.select = assert(loadstring(opts['select']))()
end
if opts['format'] then
  settings.format = assert(loadstring(opts['format']))()
end

local function metadata_exporter(task)
  local ret,conn,upstream
  local function redis_set_cb(err, data)
    if err then
      rspamd_logger.errx(task, 'got error %s when publishing record on server %s',
          err, upstream:get_addr())
      upstream:fail()
    else
      upstream:ok()
    end
  end
  if not settings.select(task) then return end
  rspamd_logger.debugx(task, 'Message selected for processing')
  ret,conn,upstream = rspamd_redis_make_request(task,
    redis_params, -- connect params
    nil, -- hash key
    true, -- is write
    redis_set_cb, --callback
    'PUBLISH', -- command
    {channel, settings.format(task)} -- arguments
  )
end

rspamd_config:register_symbol({
  name = 'EXPORT_METADATA',
  type = 'postfilter',
  callback = metadata_exporter,
  priority = 10
})
