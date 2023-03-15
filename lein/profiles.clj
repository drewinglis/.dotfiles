{:user {:aliases {"refresh" ["do" "monolith" "each" ":refresh" "build"
                             ":upstream" ":skip" :project/name ":parallel"
                             "4" "install,"]}
        :dependencies [[hashp "0.1.1"]
                       [pjstadig/humane-test-output "0.10.0"]]
        :injections [(require 'hashp.core)
                     (require 'pjstadig.humane-test-output)
                     (pjstadig.humane-test-output/activate!)]
        ;;:middleware [whidbey.plugin/repl-pprint]
        :plugins [[com.jakemccrary/lein-test-refresh "0.24.1"]
                  [lein-ancient "0.6.15"]
                  ;[lein-cprint "1.3.3"]
                  [lein-monolith "1.7.0"]
                  [mvxcvi/whidbey "2.2.1"
                   :exclusions [org.clojure/clojure]]]
        :test-refresh {:notify-command ["/usr/local/bin/terminal-notifier"
                                        "-group" "lein-test-refresh" "-title"
                                        "lein test-refresh" "-message"]
                       :changes-only true}
        :whidbey {:width 180
                  :map-delimiter ""
                  :extend-notation true
                  :print-meta true
                  :color-scheme {:nil [:blue]}}}}
