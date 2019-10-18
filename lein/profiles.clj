{:user {:plugins [[mvxcvi/whidbey "2.1.1"]
                  [com.jakemccrary/lein-test-refresh "0.24.1"]
                  [lein-monolith "1.2.0"]]
        :aliases {"refresh" ["do" "monolith" "each" ":refresh" "build"
                             ":upstream" ":skip" :project/name ":parallel"
                             "4" "install,"]}
        :test-refresh {:notify-command ["/usr/local/bin/terminal-notifier"
                                        "-group" "lein-test-refresh" "-title"
                                        "lein test-refresh" "-message"]
                       :changes-only true}
        :middleware [whidbey.plugin/repl-pprint]
        :whidbey {:width 180
                  :map-delimiter ""
                  :extend-notation true
                  :print-meta true
                  :color-scheme {:nil [:blue]}}}}
