{-# LANGUAGE DeriveDataTypeable #-}
module Kafka
( module Kafka

-- ReExport
, rdKafkaVersionStr
) where

import           Control.Exception
import           Data.Typeable

import           Kafka.Internal.RdKafka
import           Kafka.Internal.RdKafkaEnum

-- | Topic name to be consumed
--
-- Wildcard (regex) topics are supported by the librdkafka assignor:
-- any topic name in the topics list that is prefixed with @^@ will
-- be regex-matched to the full list of topics in the cluster and matching
-- topics will be added to the subscription list.
newtype TopicName =
    TopicName String -- ^ a simple topic name or a regex if started with @^@
    deriving (Show, Eq)

-- | Used to override default kafka config properties for consumers and producers
newtype KafkaProps = KafkaProps [(String, String)] deriving (Show, Eq)
emptyKafkaProps :: KafkaProps
emptyKafkaProps = KafkaProps []

-- | Used to override default topic config properties for consumers and producers
newtype TopicProps = TopicProps [(String, String)] deriving (Show, Eq)
emptyTopicProps :: TopicProps
emptyTopicProps = TopicProps []

-- | Comma separated broker:port string (e.g. @broker1:9092,broker2:9092@)
newtype BrokersString = BrokersString String deriving (Show, Eq)

-- | Timeout in milliseconds
newtype Timeout = Timeout Int deriving (Show, Eq)

-- | Kafka configuration object
data KafkaConf = KafkaConf RdKafkaConfTPtr deriving (Show)

-- | Kafka topic configuration object
data TopicConf = TopicConf RdKafkaTopicConfTPtr

-- | Main pointer to Kafka object, which contains our brokers
data Kafka = Kafka { kafkaPtr :: RdKafkaTPtr, _kafkaConf :: KafkaConf} deriving (Show)

-- | Main pointer to Kafka topic, which is what we consume from or produce to
data KafkaTopic = KafkaTopic
    RdKafkaTopicTPtr
    Kafka -- Kept around to prevent garbage collection
    TopicConf

-- | Log levels for the RdKafkaLibrary used in 'setKafkaLogLevel'
data KafkaLogLevel =
  KafkaLogEmerg | KafkaLogAlert | KafkaLogCrit | KafkaLogErr | KafkaLogWarning |
  KafkaLogNotice | KafkaLogInfo | KafkaLogDebug

instance Enum KafkaLogLevel where
   toEnum 0 = KafkaLogEmerg
   toEnum 1 = KafkaLogAlert
   toEnum 2 = KafkaLogCrit
   toEnum 3 = KafkaLogErr
   toEnum 4 = KafkaLogWarning
   toEnum 5 = KafkaLogNotice
   toEnum 6 = KafkaLogInfo
   toEnum 7 = KafkaLogDebug
   toEnum _ = undefined

   fromEnum KafkaLogEmerg = 0
   fromEnum KafkaLogAlert = 1
   fromEnum KafkaLogCrit = 2
   fromEnum KafkaLogErr = 3
   fromEnum KafkaLogWarning = 4
   fromEnum KafkaLogNotice = 5
   fromEnum KafkaLogInfo = 6
   fromEnum KafkaLogDebug = 7

-- | Any Kafka errors
data KafkaError =
    KafkaError String
  | KafkaInvalidReturnValue
  | KafkaBadSpecification String
  | KafkaResponseError RdKafkaRespErrT
  | KafkaInvalidConfigurationValue String
  | KafkaUnknownConfigurationKey String
  | KakfaBadConfiguration
    deriving (Eq, Show, Typeable)

instance Exception KafkaError

-- | Sets library log level (noisiness) with respect to a kafka instance
setLogLevel :: Kafka -> KafkaLogLevel -> IO ()
setLogLevel (Kafka kptr _) level =
  rdKafkaSetLogLevel kptr (fromEnum level)


