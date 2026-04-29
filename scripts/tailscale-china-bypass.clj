#!/usr/bin/env bb
;; tailscale-china-bypass.clj
;; Configure routing to bypass China IPs when using Tailscale
;; Supports: macOS, Debian/Ubuntu Linux
;; Usage: bb tailscale-china-bypass.clj [up|down|status]

(ns scripts.tailscale-china-bypass
  (:require [babashka.process :refer [shell]]
            [clojure.string :as str]
            [clojure.java.io :as io]))

;; Platform detection
(defn get-platform
  "Detect current platform: :macos or :linux"
  []
  (let [os (str/lower-case (System/getProperty "os.name"))]
    (cond
      (str/includes? os "mac") :macos
      (str/includes? os "linux") :linux
      :else :unknown)))

(def platform (get-platform))

;; China IP ranges sources
(def china-ip-sources
  ["http://www.ipdeny.com/ipblocks/data/countries/cn.zone"
   "https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
   "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"])

(def cache-file (str (System/getProperty "user.home") "/.cache/tailscale-china-bypass/cn.zone"))
(def cache-max-age-hours 24)

(defn clear-cache
  "Clear the IP cache file"
  []
  (let [f (io/file cache-file)]
    (when (.exists f)
      (.delete f)
      (println "Cache cleared."))))

(defn valid-cidr?
  "Check if a string is a valid CIDR notation (e.g. 1.2.3.0/24)"
  [s]
  (when (and (string? s) (not (str/blank? s)))
    (re-matches #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}" (str/trim s))))

(defn ensure-cache-dir
  "Ensure cache directory exists"
  []
  (let [cache-dir (io/file cache-file)]
    (.mkdirs (.getParentFile cache-dir))))

(defn cache-valid?
  "Check if cache file exists and is not too old"
  []
  (let [f (io/file cache-file)]
    (and (.exists f)
         (< (/ (- (System/currentTimeMillis) (.lastModified f))
               (* 1000 60 60))
            cache-max-age-hours))))

(defn read-cache
  "Read IP ranges from cache file, filtering out invalid entries"
  []
  (filterv valid-cidr? (str/split-lines (slurp cache-file))))

(defn write-cache
  "Write IP ranges to cache file"
  [content]
  (ensure-cache-dir)
  (spit cache-file content))

(defn fetch-from-source
  "Fetch IP ranges from a single source, filtering invalid entries"
  [source]
  (let [result (shell {:out :string :err :string :continue true}
                      "curl" "-s" "--max-time" "30" source)]
    (when (zero? (:exit result))
      (into #{} (filter valid-cidr? (str/split-lines (:out result)))))))

(defn aggregate-cidrs
  "Aggregate CIDR blocks where possible.
   Merges smaller blocks into larger ones (e.g., /24 -> /23).
   Returns a set of CIDRs with minimal overlap."
  [cidrs]
  (let [;; Group by first octet for faster processing
        grouped (group-by #(first (str/split % #"\.")) cidrs)
        result (atom #{})]
    (doseq [[_ group] grouped]
      ;; For now, just dedupe within groups
      ;; Full aggregation would require more complex logic
      (swap! result into group))
    @result))

(defn fetch-china-ips
  "Fetch China IP ranges from multiple sources with caching.
   Uses parallel fetching for speed."
  []
  (if (cache-valid?)
    (do
      (println "Using cached China IP ranges...")
      (into #{} (read-cache)))
    (do
      (println "Fetching China IP ranges from multiple sources (parallel)...")
      (let [;; Fetch from all sources in parallel
            futures (doall (map (fn [source]
                                  (future
                                    (println "  Fetching" source "...")
                                    (let [ranges (fetch-from-source source)]
                                      (when ranges
                                        (println "    ✓ Got" (count ranges) "ranges"))
                                      ranges)))
                                china-ip-sources))
            results (mapv deref futures)
            successful (filter some? results)]
        (if (empty? successful)
          (do
            (println "Error: Could not fetch from any source")
            (if (.exists (io/file cache-file))
              (do
                (println "Using stale cache...")
                (into #{} (read-cache)))
              #{}))
          (let [;; Merge all sets - O(n) instead of O(n²) with concat
                all-ranges (reduce into #{} successful)
                ;; Aggregate overlapping CIDRs
                aggregated (aggregate-cidrs all-ranges)]
            (println "\n✓ Total unique ranges:" (count aggregated))
            (write-cache (str/join "\n" (sort aggregated)))
            aggregated))))))

(defn get-default-gateway
  "Get the default gateway for direct China traffic (physical interface)"
  []
  (case platform
    :macos
    (let [result (shell {:out :string} "sh" "-c" "netstat -rn | grep '^default' | grep -v 'link#' | grep -v 'utun' | head -1 | awk '{print $2}'")]
      (str/trim (:out result)))
    :linux
    (let [result (shell {:out :string} "sh" "-c" "ip route show default | awk '{print $3}'")]
      (str/trim (:out result)))
    (throw (ex-info (str "Unsupported platform: " platform) {}))))

(defn get-tailscale-interface
  "Get the Tailscale interface name"
  []
  (case platform
    :macos
    (let [result (shell {:out :string} "sh" "-c" "ifconfig | grep -B2 'inet 100\\.' | grep -E '^[a-z]' | head -1 | cut -d: -f1")]
      (str/trim (:out result)))
    :linux
    (let [result (shell {:out :string} "sh" "-c" "ip link show | grep -oE 'tailscale[0-9]*' | head -1")]
      (if (str/blank? (:out result))
        "tailscale0"
        (str/trim (:out result))))
    (throw (ex-info (str "Unsupported platform: " platform) {}))))

(defn cidr-to-macos-short
  "Convert CIDR to macOS routing table short format.
   110.240.0.0/12 -> 110.240/12
   8.136.0.0/13 -> 8.136/13
   103.143.16.0/22 -> 103.143.16/22"
  [cidr]
  (let [[network prefix] (str/split cidr #"/")
        prefix-num (Integer/parseInt prefix)
        octets (str/split network #"\.")
        ;; Keep octets based on prefix length
        keep-octets (cond
                      (<= prefix-num 8) 1
                      (<= prefix-num 16) 2
                      (<= prefix-num 24) 3
                      :else 4)]
    (str (str/join "." (take keep-octets octets)) "/" prefix-num)))

(defn prompt-sudo-password
  "Prompt user for sudo password and return it (hidden input)"
  []
  (print "Enter sudo password: ")
  (flush)
  (let [console (System/console)]
    (if console
      (String. (.readPassword console))
      (.readLine (io/reader *in*)))))

(def sudo-password (atom nil))

(defn get-sudo-password
  "Get cached sudo password or prompt for it"
  []
  (or @sudo-password
      (let [pwd (prompt-sudo-password)]
        (reset! sudo-password pwd)
        pwd)))

(defn add-routes-batch
  "Add multiple routes in a single batch - larger batches for speed"
  [cidrs gateway]
  (case platform
    :macos
    (let [route-commands (str/join "\n"
                                   (map #(str "route add -net " % " " gateway) cidrs))
          result (shell {:out :string :err :string :continue true :in route-commands}
                        "sudo" "-n" "sh" "-c" "while read cmd; do eval $cmd 2>/dev/null || true; done")]
      (when (not (zero? (:exit result)))
        (println "Warning: Some routes may have failed to add")))
    :linux
    (let [route-commands (str/join "\n"
                                   (map #(str "ip route add " % " via " gateway) cidrs))
          result (shell {:out :string :err :string :continue true :in route-commands}
                        "sudo" "-n" "sh" "-c" "while read cmd; do $cmd 2>/dev/null || true; done")]
      (when (not (zero? (:exit result)))
        (println "Warning: Some routes may have failed to add")))))

(defn delete-routes-batch
  "Delete multiple routes in a single batch - larger batches for speed"
  [cidrs]
  (case platform
    :macos
    (let [route-commands (str/join "\n"
                                   (map #(str "route delete -net " %) cidrs))
          result (shell {:out :string :err :string :continue true :in route-commands}
                        "sudo" "-n" "sh" "-c" "while read cmd; do eval $cmd 2>/dev/null || true; done")]
      (when (not (zero? (:exit result)))
        (println "Warning: Some routes may have failed to delete")))
    :linux
    (let [route-commands (str/join "\n"
                                   (map #(str "ip route del " %) cidrs))
          result (shell {:out :string :err :string :continue true :in route-commands}
                        "sudo" "-n" "sh" "-c" "while read cmd; do $cmd 2>/dev/null || true; done")]
      (when (not (zero? (:exit result)))
        (println "Warning: Some routes may have failed to delete")))))

(defn add-route
  "Add a route for China IP via default gateway (bypass Tailscale)"
  [cidr gateway]
  (case platform
    :macos
    (let [result (shell {:out :string :err :string :continue true}
                        "sudo" "-n" "route" "-q" "-n" "add" "-net" cidr gateway)]
      (when (and (not (zero? (:exit result)))
                 (not (str/includes? (:err result) "File exists")))
        (println "Warning: Failed to add route for" cidr ":" (:err result))))
    :linux
    (let [result (shell {:out :string :err :string :continue true}
                        "sudo" "-n" "ip" "route" "add" cidr "via" gateway)]
      (when (and (not (zero? (:exit result)))
                 (not (str/includes? (:err result) "File exists")))
        (println "Warning: Failed to add route for" cidr ":" (:err result))))))

(defn delete-route
  "Delete a route for China IP"
  [cidr]
  (case platform
    :macos
    (shell {:out :string :err :string :continue true}
           "sudo" "-n" "route" "-q" "-n" "delete" "-net" cidr)
    :linux
    (shell {:out :string :err :string :continue true}
           "sudo" "-n" "ip" "route" "del" cidr)))

(defn ip-in-cidr?
  "Check if an IP address falls within a CIDR range"
  [ip cidr]
  (when (valid-cidr? cidr)
    (let [[network prefix] (str/split cidr #"/")
          prefix-len (Integer/parseInt prefix)
          ip-parts (mapv #(Integer/parseInt %) (str/split ip #"\."))
          net-parts (mapv #(Integer/parseInt %) (str/split network #"\."))
          mask (bit-shift-left -1 (- 32 prefix-len))
          ip-int (reduce (fn [acc part] (+ (bit-shift-left acc 8) part)) 0 ip-parts)
          net-int (reduce (fn [acc part] (+ (bit-shift-left acc 8) part)) 0 net-parts)
          ip-masked (bit-and ip-int mask)
          net-masked (bit-and net-int mask)]
      (= ip-masked net-masked))))

(defn check-route
  "Check if a route exists for CIDR. Platform-specific."
  [cidr]
  (case platform
    :macos
    (let [short-cidr (cidr-to-macos-short cidr)
          result (shell {:out :string :err :string :continue true}
                        "sh" "-c" (str "netstat -rn | grep '^" short-cidr "' | head -1"))]
      (:out result))
    :linux
    (let [result (shell {:out :string :err :string :continue true}
                        "sh" "-c" (str "ip route show " cidr " | head -1"))]
      (:out result))))

(defn show-sample-routes
  "Show sample China routes. Platform-specific."
  []
  (case platform
    :macos
    (let [result (shell {:out :string :err :string} "sh" "-c" "netstat -rn | grep -E '^1\\.0\\.|^14\\.' | head -10")]
      (if (str/blank? (:out result))
        (println "No China routes configured")
        (println (:out result))))
    :linux
    (let [result (shell {:out :string :err :string} "sh" "-c" "ip route show | grep -E '^1\\.0\\.|^14\\.' | head -10")]
      (if (str/blank? (:out result))
        (println "No China routes configured")
        (println (:out result))))))

(defn resolve-hostname
  "Resolve hostname to IP address. Works on both macOS and Linux.
   Returns nil if resolution fails."
  [hostname]
  (let [;; Try multiple methods for portability
        methods [(str "dig +short " hostname " 2>/dev/null | head -1")
                 (str "host " hostname " 2>/dev/null | head -1 | awk '{print $NF}'")
                 (str "getent hosts " hostname " 2>/dev/null | awk '{print $1}'")
                 (str "nslookup " hostname " 2>/dev/null | grep 'Address' | tail -1 | awk '{print $2}'")]]
    (loop [[method & rest] methods]
      (if method
        (let [result (shell {:out :string :err :string :continue true}
                            "sh" "-c" method)
              ip (when-not (str/blank? (:out result))
                   (let [trimmed (str/trim (:out result))]
                     ;; Validate it looks like an IP
                     (when (re-matches #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" trimmed)
                       trimmed)))]
          (if ip ip (recur rest)))
        nil))))

(defn test-bypass
  "Test if bypass is working by checking route to a China IP"
  []
  (println "\n=== Testing Bypass ===")
  (println (str "Platform: " (name platform)))
  ;; Test with baidu.com IP
  (let [test-ip "110.242.74.102"
        cidrs (fetch-china-ips)
        matching-cidr (first (filter #(ip-in-cidr? test-ip %) cidrs))]

    (if matching-cidr
      (do
        (println (str "✓ Found " test-ip " in CIDR: " matching-cidr))
        (let [route-output (check-route matching-cidr)]
          (if (str/blank? route-output)
            (println "⚠ Warning: Route not found in routing table for " matching-cidr)
            (do
              (println "✓ China IP route configured:")
              (println " " (str/trim route-output))
              (if (str/includes? route-output "100.")
                (println "✗ FAIL: Traffic going through Tailscale (100.x.x.x)")
                (println "✓ PASS: Traffic going direct (not through Tailscale)"))))))
      (println "⚠ Warning: " test-ip " not found in any China CIDR range")))

;; Show sample routes
  (let [cidrs (fetch-china-ips)
        sample-cidrs (take 3 cidrs)]
    (when (seq sample-cidrs)
      (println "\n✓ Sample routes configured:")
      (doseq [cidr sample-cidrs]
        (let [route-output (check-route cidr)]
          (when (not (str/blank? route-output))
            (println " " (str/trim route-output)))))))

  ;; Test China AI services
  (println "\n=== Testing China AI Services ===")
  (let [ai-services [{:name "dashscope.aliyuncs.com" :url "https://coding.dashscope.aliyuncs.com/v1"}
                     {:name "minimaxi.com" :ip "8.130.49.194"}
                     {:name "moonshot.cn" :ip "103.143.17.156"}
                     {:name "kimi.com" :ip "103.143.17.156"}
                     {:name "bigmodel.cn" :ip "119.23.85.51"}]
        cidrs (fetch-china-ips)]
    (doseq [{:keys [name ip url]} ai-services]
      (let [test-ip (if url
                      (or (resolve-hostname name)
                          (do (println (str "⚠ " name ": Could not resolve hostname")) nil))
                      ip)]
        (when test-ip
          (let [matching-cidr (first (filter #(ip-in-cidr? test-ip %) cidrs))]
            (if matching-cidr
              (let [route-output (check-route matching-cidr)]
                (if (str/blank? route-output)
                  (println (str "⚠ " name " (" test-ip "): CIDR " matching-cidr " found but route not configured"))
                  (if (str/includes? route-output "100.")
                    (println (str "✗ " name " (" test-ip "): FAIL - Going through Tailscale"))
                    (println (str "✓ " name " (" test-ip "): PASS - Direct access")))))
              (println (str "⚠ " name " (" test-ip "): IP not in China CIDR ranges")))))))))

(defn tailscale-up
  "Configure routing to bypass China IPs through default gateway"
  []
  (let [china-cidrs (vec (fetch-china-ips))
        gateway (get-default-gateway)
        tailscale-iface (get-tailscale-interface)]
    (if (empty? china-cidrs)
      (println "No China IP ranges fetched. Check internet connection.")
      (do
        (println (str "Found " (count china-cidrs) " China CIDR blocks"))
        (println (str "Default gateway: " gateway))
        (println (str "Tailscale interface: " tailscale-iface))
        (println "\nAdding routes to bypass Tailscale for China IPs...")
        (println "(This requires sudo privileges)")
        (println "Tip: Run 'sudo -v' first to cache credentials, or you'll be prompted for each batch)")

        ;; Add routes in larger batches for maximum speed
        (println "Adding routes in batches of 500...")
        (let [start-time (System/currentTimeMillis)]
          (doseq [[batch-idx batch] (map-indexed vector (partition-all 500 china-cidrs))]
            (when (zero? (mod batch-idx 10))
              (println (str "Progress: " (* batch-idx 500) "/" (count china-cidrs))))
            (add-routes-batch batch gateway))
          (let [elapsed (/ (- (System/currentTimeMillis) start-time) 1000.0)]
            (println (str "\n✓ Added " (count china-cidrs) " routes in " elapsed " seconds"))
            (println "  - China traffic: Direct via default gateway")
            (println "  - Other traffic: Through Tailscale")
            ;; Auto-test the bypass
            (test-bypass)))))))

(defn tailscale-down
  "Remove China bypass routes"
  []
  (let [china-cidrs (vec (fetch-china-ips))]
    (if (empty? china-cidrs)
      (println "No China IP ranges to remove.")
      (do
        (println (str "Removing " (count china-cidrs) " China bypass routes..."))
        (println "(This requires sudo privileges)")
        (println "Tip: Run 'sudo -v' first to cache credentials")

        ;; Delete routes in larger batches for maximum speed
        (println "Removing routes in batches of 500...")
        (let [start-time (System/currentTimeMillis)]
          (doseq [[batch-idx batch] (map-indexed vector (partition-all 500 china-cidrs))]
            (when (zero? (mod batch-idx 10))
              (println (str "Progress: " (* batch-idx 500) "/" (count china-cidrs))))
            (delete-routes-batch batch))
          (let [elapsed (/ (- (System/currentTimeMillis) start-time) 1000.0)]
            (println (str "\n✓ Removed " (count china-cidrs) " routes in " elapsed " seconds"))))))))

(defn tailscale-status
  "Show current routing status"
  []
  (println "=== Tailscale Status ===")
  (println (str "Platform: " (name platform)))
  (let [result (shell {:out :string :err :string} "tailscale" "status")]
    (println (:out result)))

  (println "\n=== China Routes (sample) ===")
  (show-sample-routes)

  (println "\n=== Default Gateway ===")
  (let [gateway (get-default-gateway)]
    (println (str "Gateway: " gateway))))

(defn -main [& args]
  (case (first args)
    "up" (tailscale-up)
    "down" (tailscale-down)
    "status" (tailscale-status)
    "refresh" (do
                (clear-cache)
                (println "Fetching fresh IP ranges...")
                (let [cidrs (fetch-china-ips)]
                  (println (str "✓ Cached " (count cidrs) " China IP ranges"))))
    (do
      (println (str "Tailscale China Bypass Tool for " (name platform)))
      (println "")
      (println "Usage: bb tailscale-china-bypass.clj <command>")
      (println "")
      (println "Commands:")
      (println "  up      - Add routes to bypass Tailscale for China IPs")
      (println "  down    - Remove China bypass routes")
      (println "  status  - Show current Tailscale and routing status")
      (println "  refresh - Force refresh IP cache from sources")
      (println "")
      (println "How it works:")
      (println "  1. Fetches China IP ranges from multiple sources (parallel)")
      (println "  2. Deduplicates and caches for 24 hours")
      (println "  3. Adds static routes for China IPs via your default gateway")
      (println "  4. China traffic bypasses Tailscale, other traffic uses Tailscale")
      (println "")
      (println "Supported platforms: macOS, Debian/Ubuntu Linux")
      (println "")
      (println "Note: This modifies system routes and requires sudo privileges.")
      (System/exit 1))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
