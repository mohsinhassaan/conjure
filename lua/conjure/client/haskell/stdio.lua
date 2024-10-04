-- [nfnl] Compiled from fnl/conjure/client/haskell/stdio.fnl by https://github.com/Olical/nfnl, do not edit.
local _local_1_ = require("nfnl.module")
local autoload = _local_1_["autoload"]
local a = autoload("conjure.aniseed.core")
local extract = autoload("conjure.extract")
local str = autoload("conjure.aniseed.string")
local stdio = autoload("conjure.remote.stdio")
local config = autoload("conjure.config")
local text = autoload("conjure.text")
local mapping = autoload("conjure.mapping")
local client = autoload("conjure.client")
local log = autoload("conjure.log")
local ts = autoload("conjure.tree-sitter")
local b64 = autoload("conjure.remote.transport.base64")
config.merge({client = {haskell = {stdio = {command = "ghci", ["prompt-pattern"] = "ghci> "}}}})
if config["get-in"]({"mapping", "enable_defaults"}) then
  config.merge({client = {haskell = {stdio = {mapping = {start = "cs", stop = "cS", interrupt = "ei"}}}}})
else
end
local cfg = config["get-in-fn"]({"client", "haskell", "stdio"})
local state
local function _3_()
  return {repl = nil}
end
state = client["new-state"](_3_)
local buf_suffix = ".hs"
local comment_prefix = "-- "
local function form_node_3f(node)
  return (("top_splice" == node:type()) or ("import_statement" == node:type()) or ("type_synomym" == node:type()) or ("class" == node:type()) or ("data_type" == node:type()) or ("instance" == node:type()) or ("bind" == node:type()) or ("function" == node:type()))
end
local function with_repl_or_warn(f, opts)
  local repl = state("repl")
  if repl then
    return f(repl)
  else
    return log.append({(comment_prefix .. "No REPL running"), (comment_prefix .. "Start REPL with " .. config["get-in"]({"mapping", "prefix"}) .. cfg({"mapping", "start"}))})
  end
end
local function prep_code(s)
  return (":{\n" .. text["trim-last-newline"](s) .. "\n:}\n")
end
local function format_msg(msg)
  local function _5_(_241)
    return ("" ~= _241)
  end
  return a.filter(_5_, text["split-lines"](msg))
end
local function get_console_output_msgs(msgs)
  local function _6_(_241)
    return (comment_prefix .. "(out) " .. _241)
  end
  return a.map(_6_, a.butlast(msgs))
end
local function get_expression_result(msgs)
  local result = a.last(msgs)
  if a["nil?"](result) then
    return nil
  else
    return result
  end
end
local function unbatch(msgs)
  local function _8_(_241)
    return (a.get(_241, "err") or a.get(_241, "out"))
  end
  return str.join("", a.map(_8_, msgs))
end
local function log_repl_output(msgs)
  local msgs0 = format_msg(unbatch(msgs))
  local console_output_msgs = get_console_output_msgs(msgs0)
  local cmd_result = get_expression_result(msgs0)
  if not a["empty?"](console_output_msgs) then
    log.append(console_output_msgs)
  else
  end
  if cmd_result then
    return log.append({cmd_result})
  else
    return nil
  end
end
local function eval_str(opts)
  local function _11_(repl)
    local function _12_(msgs)
      log_repl_output(msgs)
      if opts["on-result"] then
        local msgs0 = format_msg(unbatch(msgs))
        local cmd_result = get_expression_result(msgs0)
        return opts["on-result"](cmd_result)
      else
        return nil
      end
    end
    return repl.send(prep_code(opts.code), _12_, {["batch?"] = true})
  end
  return with_repl_or_warn(_11_)
end
local function eval_file(opts)
  return eval_str(a.assoc(opts, "code", a.slurp(opts["file-path"])))
end
local function display_repl_status(status)
  return log.append({(comment_prefix .. cfg({"command"}) .. " (" .. (status or "no status") .. ")")}, {["break?"] = true})
end
local function stop()
  local repl = state("repl")
  if repl then
    repl.destroy()
    display_repl_status("stopped")
    return a.assoc(state(), "repl", nil)
  else
    return nil
  end
end
local initialise_repl_code = str.join("\n", {":set prompt-cont \"\"", "\n"})
local function start()
  log.append({(comment_prefix .. "Starting Haskell client...")})
  if state("repl") then
    return log.append({(comment_prefix .. "Can't start, REPL is already running."), (comment_prefix .. "Stop the REPL with " .. config["get-in"]({"mapping", "prefix"}) .. cfg({"mapping", "stop"}))}, {["break?"] = true})
  else
    local function _15_()
      if vim.treesitter.language.require_language then
        return vim.treesitter.language.require_language("haskell")
      else
        return vim.treesitter.require_language("haskell")
      end
    end
    if not pcall(_15_) then
      return log.append({(comment_prefix .. "(error) The haskell client requires a haskell treesitter parser in order to function."), (comment_prefix .. "(error) See https://github.com/nvim-treesitter/nvim-treesitter"), (comment_prefix .. "(error) for installation instructions.")})
    else
      local function _17_()
        local function _18_(repl)
          local function _19_(msgs)
            return nil
          end
          return repl.send(initialise_repl_code, _19_, nil)
        end
        return display_repl_status("started", with_repl_or_warn(_18_))
      end
      local function _20_(err)
        return display_repl_status(err)
      end
      local function _21_(code, signal)
        if (("number" == type(code)) and (code > 0)) then
          log.append({(comment_prefix .. "process exited with code " .. code)})
        else
        end
        if (("number" == type(signal)) and (signal > 0)) then
          log.append({(comment_prefix .. "process exited with signal " .. signal)})
        else
        end
        return stop()
      end
      local function _24_(msg)
        return log.dbg(format_msg(unbatch({msg})))
      end
      return a.assoc(state(), "repl", stdio.start({["prompt-pattern"] = cfg({"prompt-pattern"}), cmd = cfg({"command"}), ["delay-stderr-ms"] = cfg({"delay-stderr-ms"}), ["on-success"] = _17_, ["on-error"] = _20_, ["on-exit"] = _21_, ["on-stray-output"] = _24_}))
    end
  end
end
local function on_exit()
  return stop()
end
local function interrupt()
  local function _27_(repl)
    log.append({(comment_prefix .. " Sending interrupt signal.")}, {["break?"] = true})
    return repl["send-signal"](vim.loop.constants.SIGINT)
  end
  return with_repl_or_warn(_27_)
end
local function on_load()
  if config["get-in"]({"client_on_load"}) then
    return start()
  else
    return nil
  end
end
local function on_filetype()
  mapping.buf("HaskellStart", cfg({"mapping", "start"}), start, {desc = "Start the Haskell REPL"})
  mapping.buf("HaskellStop", cfg({"mapping", "stop"}), stop, {desc = "Stop the Haskell REPL"})
  return mapping.buf("HaskellInterrupt", cfg({"mapping", "interrupt"}), interrupt, {desc = "Interrupt the current evaluation"})
end
return {["buf-suffix"] = buf_suffix, ["comment-prefix"] = comment_prefix, ["form-node?"] = form_node_3f, ["format-msg"] = format_msg, unbatch = unbatch, ["eval-str"] = eval_str, ["eval-file"] = eval_file, stop = stop, ["initialise-repl-code"] = initialise_repl_code, start = start, ["on-load"] = on_load, ["on-exit"] = on_exit, interrupt = interrupt, ["on-filetype"] = on_filetype}
