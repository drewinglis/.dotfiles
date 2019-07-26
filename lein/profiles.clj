{:user {:plugins [;[cider/cider-nrepl "0.21.1" :exclusions [org.clojure/tools.nrepl]]
                  [lein-monolith "1.2.0"]]
        :aliases {"refresh" ["do" "monolith" "each" ":refresh" "build"
                             ":upstream" ":skip" :project/name ":parallel"
                             "4" "install,"]}}}
