{-# LANGUAGE OverloadedStrings #-}

module Kafka.Examples.ProducerExample
where

import           Kafka
import           Kafka.Producer

runProducerExample :: IO ()
runProducerExample = do
    res <- runProducer (BrokersString "localhost:9092") emptyKafkaProps sendMessages
    print $ show res

sendMessages :: Kafka -> IO String
sendMessages kafka = do
    topic <- newKafkaTopic kafka "hl-test" emptyTopicProps
    err1 <- produceMessage topic UnassignedPartition (ProduceMessage "test from producer")
    print $ show err1

    err2 <- produceMessage topic UnassignedPartition (ProduceKeyedMessage "key" "test from producer (with key)")
    print $ show err2

    return "All done, Sir."

