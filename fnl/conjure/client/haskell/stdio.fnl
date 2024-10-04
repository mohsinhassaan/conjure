(local {: autoload} (require :nfnl.module))
(local a (autoload :conjure.aniseed.core))
(local extract (autoload :conjure.extract))
(local str (autoload :conjure.aniseed.string))
(local stdio (autoload :conjure.remote.stdio))
(local config (autoload :conjure.config))
(local text (autoload :conjure.text))
(local mapping (autoload :conjure.mapping))
(local client (autoload :conjure.client))
(local log (autoload :conjure.log))
(local ts (autoload :conjure.tree-sitter))
(local b64 (autoload :conjure.remote.transport.base64))

(config.merge
  {:client
   {:haskell
    {:stdio
     {:command "ghci"
      :prompt-pattern "ghci> "}}}})

(when (config.get-in [:mapping :enable_defaults])
  (config.merge
    {:client
     {:haskell
      {:stdio
       {:mapping {:start "cs"
                  :stop "cS"
                  :interrupt "ei"}}}}}))

(local cfg (config.get-in-fn [:client :haskell :stdio]))
(local state (client.new-state #(do {:repl nil})))
(local buf-suffix ".hs")
(local comment-prefix "-- ")

; These types of nodes are roughly equivalent to Lisp forms.
; This should make it more intuitive to use <localLeader>ee to evaluate the
; "current form" and not be surprised that it wasn't what you thought.
(fn form-node?
  [node]
  (or (= "top_splice" (node:type))
      (= "import_statement" (node:type))
      (= "type_synomym" (node:type))
      (= "class" (node:type))
      (= "data_type" (node:type))
      (= "instance" (node:type))
      (= "bind" (node:type))
      (= "function" (node:type))))

(fn with-repl-or-warn [f opts]
  (let [repl (state :repl)]
    (if repl
      (f repl)
      (log.append [(.. comment-prefix "No REPL running")
                   (.. comment-prefix
                       "Start REPL with "
                       (config.get-in [:mapping :prefix])
                       (cfg [:mapping :start]))]))))

(fn prep-code
  [s]
  (.. ":{\n" (text.trim-last-newline s) "\n:}\n"))

(fn format-msg [msg]
  (->> (text.split-lines msg)
       (a.filter #(~= "" $1))))

(fn get-console-output-msgs [msgs]
  (->> (a.butlast msgs)
       (a.map #(.. comment-prefix "(out) " $1))))

(fn get-expression-result [msgs]
  (let [result (a.last msgs)]
    (if
      (a.nil? result)
      nil
      result)))

(fn unbatch [msgs]
  (->> msgs
       (a.map #(or (a.get $1 :err)
                   (a.get $1 :out)))
       (str.join "")))

(fn log-repl-output [msgs]
  (let [msgs (-> msgs unbatch format-msg)
        console-output-msgs (get-console-output-msgs msgs)
        cmd-result (get-expression-result msgs)]
    (when (not (a.empty? console-output-msgs))
      (log.append console-output-msgs))
    (when cmd-result
      (log.append [cmd-result]))))

(fn eval-str [opts]
  (with-repl-or-warn
    (fn [repl]
      (repl.send
        (prep-code opts.code)
        (fn [msgs]
          (log-repl-output msgs)
          (when opts.on-result
            (let [msgs (-> msgs unbatch format-msg)
                  cmd-result (get-expression-result msgs)]
              (opts.on-result cmd-result))))
        {:batch? true}))))

(fn eval-file [opts]
  (eval-str (a.assoc opts :code (a.slurp opts.file-path))))

(fn display-repl-status [status]
  ( log.append
    [(.. comment-prefix
         (cfg [:command])
         " (" (or status "no status") ")")]
    {:break? true}))

(fn stop []
  (let [repl (state :repl)]
    (when repl
      (repl.destroy)
      (display-repl-status :stopped)
      (a.assoc (state) :repl nil))))

(local initialise-repl-code
  (str.join
    "\n"
    [":set prompt-cont \"\""
     "\n"]))

(fn start []
  (log.append [(.. comment-prefix "Starting Haskell client...")])
  (if (state :repl)
    (log.append [(.. comment-prefix "Can't start, REPL is already running.")
                 (.. comment-prefix "Stop the REPL with "
                     (config.get-in [:mapping :prefix])
                     (cfg [:mapping :stop]))]
                {:break? true})
    (if (not (pcall #(if vim.treesitter.language.require_language
                         (vim.treesitter.language.require_language "haskell")
                         (vim.treesitter.require_language "haskell"))))
      (log.append [(.. comment-prefix "(error) The haskell client requires a haskell treesitter parser in order to function.")
                   (.. comment-prefix "(error) See https://github.com/nvim-treesitter/nvim-treesitter")
                   (.. comment-prefix "(error) for installation instructions.")])
      (a.assoc
        (state) :repl
        (stdio.start
          {:prompt-pattern (cfg [:prompt-pattern])
           :cmd (cfg [:command])
           :delay-stderr-ms (cfg [:delay-stderr-ms])

           :on-success
           (fn []
             (display-repl-status :started
              (with-repl-or-warn
               (fn [repl]
                 (repl.send
                   initialise-repl-code
                   (fn [msgs] nil)
                   nil)))))

           :on-error
           (fn [err]
             (display-repl-status err))

           :on-exit
           (fn [code signal]
             (when (and (= :number (type code)) (> code 0))
               (log.append [(.. comment-prefix "process exited with code " code)]))
             (when (and (= :number (type signal)) (> signal 0))
               (log.append [(.. comment-prefix "process exited with signal " signal)]))
             (stop))

           :on-stray-output
           (fn [msg]
             (log.dbg (-> [msg] unbatch format-msg)))})))))

(fn on-exit []
  (stop))

(fn interrupt []
  (with-repl-or-warn
    (fn [repl]
      (log.append [(.. comment-prefix " Sending interrupt signal.")] {:break? true})
      (repl.send-signal vim.loop.constants.SIGINT))))

(fn on-load []
  ;; Start up REPL only if g.conjure#client_on_load is v:true.
  (when (config.get-in [:client_on_load])
    (start)))

(fn on-filetype []
  (mapping.buf
    :HaskellStart (cfg [:mapping :start])
    start
    {:desc "Start the Haskell REPL"})

  (mapping.buf
    :HaskellStop (cfg [:mapping :stop])
    stop
    {:desc "Stop the Haskell REPL"})

  (mapping.buf
    :HaskellInterrupt (cfg [:mapping :interrupt])
    interrupt
    {:desc "Interrupt the current evaluation"}))


{: buf-suffix
 : comment-prefix
 : form-node?
 : format-msg
 : unbatch
 : eval-str
 : eval-file
 : stop
 : initialise-repl-code
 : start
 : on-load
 : on-exit
 : interrupt
 : on-filetype}
