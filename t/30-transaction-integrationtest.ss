(export #t)

(import
  :gerbil/gambit/threads
  :std/format :std/sugar :std/test
  :clan/base :clan/debug :clan/failure :clan/json :clan/option :clan/path
  :clan/poo/poo :clan/poo/io :clan/poo/debug :clan/poo/brace
  :clan/persist/db
  ../hex ../types ../network-config ../signing ../known-addresses
  ../ethereum ../json-rpc ../nonce-tracker ../transaction ../watch ../contract-runtime
  ./signing-test ./10-json-rpc-integrationtest ./20-nonce-tracker-integrationtest)

;; Send a tx, not robust, but useful for debugging
(def (debug-send-tx
      tx confirmations: (confirmations (ethereum-confirmations-wanted-in-blocks)))
  (def from (.@ tx from))
  (reset-nonce from)
  (def signed (sign-transaction tx))
  (DDT debug-send-tx-0:
       PreTransaction tx
       SignedTransactionInfo signed)
  (def receipt
    (let/cc return
      (while #t
        (try
         (ignore-errors (send-signed-transaction signed))
         (return (confirmed-receipt<-transaction signed confirmations: confirmations))
         (catch StillPending? => void)
         (catch (TransactionRejected? e) (return (TransactionRejected-receipt e))))
        (thread-sleep! (ethereum-block-polling-period-in-seconds)))))
  (def success? (successful-receipt? receipt))
  (DDT debug-send-tx-1:
       Bool success?
       (Or TransactionReceipt Any) receipt)
  (unless success? (raise (TransactionRejected receipt)))
  (values signed receipt))

;; Block can be a block number, latest, earliest, pending, or commit.
;; if commit, then commit the evaluation to be inspected with remix.ethereum.org

;; Bytes <- Address Bytes value:?(Maybe Quantity) block:?(Or BlockParameter (Enum commit))
(def (evm-eval/offchain from code value: (value (void)) block: (block 'latest))
  (eth_call {from data: code value} block))

;; TransactionReceipt <- Address Bytes value:?(Maybe Quantity)
(def (evm-eval/onchain from code value: (value (void)))
  ;; Create a contract with the code
  (defvalues (signed receipt) (debug-send-tx {from data: (stateless-contract-init code) value}))
  (def contract (.@ receipt contractAddress))
  ;; Call the contract with the value
  (debug-send-tx {from to: contract value}))

(def 30-transaction-integrationtest
  (test-suite "integration test for ethereum/transaction"
    (test-case "Send tokens from Croesus to Trent"
      (reset-nonce croesus) (DDT nonce: Any (peek-nonce croesus))
      (def value (wei<-ether 2))
      (def before (eth_getBalance trent 'latest))
      (debug-send-tx (transfer-tokens from: croesus to: trent value: value))
      (def after (eth_getBalance trent 'latest))
      (check-equal? (- after before) value))))
