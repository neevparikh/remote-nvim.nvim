---@class remote-nvim.providers.Executor: remote-nvim.Object
---@field host string Host name
---@field conn_opts string Connection options (passed when connecting)
---@field protected _job_id integer? Job ID of the current job
---@field protected _job_exit_code integer? Exit code of the job on the executor
---@field protected _job_stdout string[] Job output (if job is running)
local Executor = require("remote-nvim.middleclass")("Executor")

---@class remote-nvim.provider.Executor.JobOpts.CompressionOpts
---@field enabled boolean Apply compression
---@field additional_opts? string[] Additional options to pass to the `tar` command. See `man tar` for possible options

---@class remote-nvim.provider.Executor.JobOpts
---@field additional_conn_opts string? Connection options
---@field stdout_cb function? Standard output callback
---@field exit_cb function? On exit callback
---@field compression remote-nvim.provider.Executor.JobOpts.CompressionOpts? Compression options; for upload and download

---Initialize executor instance
---@param host string Host name
---@param conn_opts? string Connection options (passed when connecting)
function Executor:init(host, conn_opts)
  self.host = host
  self.conn_opts = conn_opts or ""

  self._job_id = nil
  self._job_exit_code = nil
  self._job_stdout = {}
end

---@protected
---Reset executor state
function Executor:reset()
  self._job_id = nil
  self._job_exit_code = nil
  self._job_stdout = {}
end

-- selene: allow(unused_variable)

---Upload data to the host
---@param localSrcPath string Local path from which data would be uploaded
---@param remoteDestPath string Path on host where data would be uploaded
---@param job_opts remote-nvim.provider.Executor.JobOpts
---@diagnostic disable-next-line: unused-local
function Executor:upload(localSrcPath, remoteDestPath, job_opts)
  error("Not implemented")
end

-- selene: allow(unused_variable)

---Download data from host
---@param remoteSrcPath string Remote path where data is located
---@param localDestPath string Local path where data will be downloaded
---@param job_opts remote-nvim.provider.Executor.JobOpts
---@diagnostic disable-next-line: unused-local
function Executor:download(remoteSrcPath, localDestPath, job_opts)
  error("Not implemented")
end

---Run command on host
---@param command string Command to run on the remote host
---@param job_opts remote-nvim.provider.Executor.JobOpts
function Executor:run_command(command, job_opts)
  return self:run_executor_job(command, job_opts)
end

---@protected
---@async
---Run the job over executor
---@param command string Command which should be started as a job
---@param job_opts remote-nvim.provider.Executor.JobOpts
function Executor:run_executor_job(command, job_opts)
  local co = coroutine.running()
  job_opts = job_opts or {}

  self:reset() -- Reset job internal state variables
  self._job_id = vim.fn.jobstart(command, {
    pty = false,
    on_stdout = function(_, data_chunk)
      self:process_stdout(data_chunk, job_opts.stdout_cb)
    end,
    on_exit = function(_, exit_code)
      self:process_job_completion(exit_code)
      if job_opts.exit_cb ~= nil then
        job_opts.exit_cb(exit_code)
      end
      if co ~= nil then
        coroutine.resume(co)
      end
    end,
  })

  if co ~= nil then
    return coroutine.yield(self)
  end

  return self
end

---@protected
---Process output generated by stdout
---@param output_chunks string[]
---@param cb function? Callback to call on job output
function Executor:process_stdout(output_chunks, cb)
  for _, chunk in ipairs(output_chunks) do
    local cleaned_chunk = chunk:gsub("\r", "\n")
    table.insert(self._job_stdout, cleaned_chunk)
    if cb ~= nil then
      cb(cleaned_chunk)
    end
  end
end

---@protected
---Process job completion
---@param exit_code number Exit code of the job running on the executor
function Executor:process_job_completion(exit_code)
  self._job_exit_code = exit_code
end

---Get last/current job ID
---@return integer? job_id
function Executor:last_job_id()
  return self._job_id
end

---Get last job's status (exit code)
function Executor:last_job_status()
  assert(self._job_id ~= nil, "No jobs running")
  return self._job_exit_code or vim.fn.jobwait({ self._job_id }, 0)[1]
end

---Cancel running job on executor
---@return number status_code Returns 1 for valid job id, 0 for exited, stopped or invalid jobs
function Executor:cancel_running_job()
  assert(self._job_id ~= nil, "No running job to be cancelled")
  return vim.fn.jobstop(self._job_id)
end

---Get output generated by job running on the executor
---@return string[] stdout Job output separated by new lines
function Executor:job_stdout()
  return vim.split(vim.trim(table.concat(self._job_stdout, "")), "\n")
end

return Executor
