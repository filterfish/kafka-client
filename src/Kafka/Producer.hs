module Kafka.Producer
( runProducerConf
, runProducer
, newProducerConf
, newProducer
, produceMessage
, produceMessageBatch
, drainOutQueue
, IS.newKafkaTopic
, PIT.ProduceMessage (..)
, PIT.ProducePartition (..)
, RDE.RdKafkaRespErrT (..)
)
where

import           Control.Exception
import           Control.Monad
import qualified Data.ByteString                 as BS
import qualified Data.ByteString.Internal        as BSI
import           Foreign                         hiding (void)
import           Kafka
import           Kafka.Internal.RdKafka
import           Kafka.Internal.RdKafkaEnum
import           Kafka.Internal.Setup
import           Kafka.Producer.Internal.Convert
import           Kafka.Producer.Internal.Types

import qualified Kafka.Internal.RdKafkaEnum      as RDE
import qualified Kafka.Internal.Setup            as IS
import qualified Kafka.Producer.Internal.Types   as PIT

runProducerConf :: BrokersString
                -> KafkaConf
                -> (Kafka -> IO a)
                -> IO a
runProducerConf bs c f =
    bracket mkProducer clProducer runHandler
    where
        mkProducer = newProducer bs c
        clProducer = drainOutQueue
        runHandler = f

runProducer :: BrokersString    -- ^ Comma separated list of brokers with ports (e.g. @localhost:9092@)
            -> KafkaProps       -- ^ Extra kafka producer parameters (see kafka documentation)
            -> (Kafka -> IO a)
            -> IO a
runProducer bs c f = do
    conf <- newProducerConf c
    runProducerConf bs conf f

-- | Creates a new kafka configuration for a producer'.
newProducerConf :: KafkaProps    -- ^ Extra kafka producer parameters (see kafka documentation)
                -> IO KafkaConf  -- ^ Kafka configuration which can be altered before it is used in 'newProducer'
newProducerConf =
    kafkaConf

-- | Creates a new kafka producer
newProducer :: BrokersString -- ^ Comma separated list of brokers with ports (e.g. @localhost:9092@)
            -> KafkaConf     -- ^ Kafka configuration for a producer (see 'newProducerConf')
            -> IO Kafka      -- ^ Kafka instance
newProducer (BrokersString bs) conf = do
    kafka <- newKafkaPtr RdKafkaProducer conf
    addBrokers kafka bs
    return kafka

-- | Produce a single unkeyed message to either a random partition or specified partition. Since
-- librdkafka is backed by a queue, this function can return before messages are sent. See
-- 'drainOutQueue' to wait for queue to empty.
produceMessage :: KafkaTopic             -- ^ target topic
               -> ProducePartition  -- ^ the "default" target partition. Only used for messages with no message key specified.
               -> ProduceMessage    -- ^ the message to enqueue. This function is undefined for keyed messages.
               -> IO (Maybe KafkaError)  -- ^ 'Nothing' on success, error if something went wrong.
produceMessage (KafkaTopic t _ _) p m =
    let (key, payload) = keyAndPayload m
    in  withBS (Just payload) $ \payloadPtr payloadLength ->
            withBS key $ \keyPtr keyLength ->
                let realPart = if keyLength == 0 then p else UnassignedPartition
                in  handleProduceErr =<<
                        rdKafkaProduce t (producePartitionCInt realPart)
                          copyMsgFlags payloadPtr (fromIntegral payloadLength)
                          keyPtr (fromIntegral keyLength) nullPtr

-- | Produce a batch of messages. Since librdkafka is backed by a queue, this function can return
-- before messages are sent. See 'drainOutQueue' to wait for the queue to be empty.
produceMessageBatch :: KafkaTopic  -- ^ topic pointer
                    -> ProducePartition -- ^ the "default" target partition. Only used for messages with no message key specified.
                    -> [ProduceMessage] -- ^ list of messages to enqueue.
                    -> IO [(ProduceMessage, KafkaError)] -- list of failed messages with their errors. This will be empty on success.
produceMessageBatch (KafkaTopic t _ _) p pms = do
  msgs <- forM pms toNativeMessage
  let msgsCount = length msgs
  withArray msgs $ \batchPtr -> do
    batchPtrF <- newForeignPtr_ batchPtr
    numRet    <- rdKafkaProduceBatch t (producePartitionCInt p) copyMsgFlags batchPtrF msgsCount
    if numRet == msgsCount then return []
    else do
      errs <- mapM (return . err'RdKafkaMessageT <=< peekElemOff batchPtr)
                   [0..(fromIntegral $ msgsCount - 1)]
      return [(m, KafkaResponseError e) | (m, e) <- zip pms errs, e /= RdKafkaRespErrNoError]
  where
      toNativeMessage msg =
          let (key, payload) = keyAndPayload msg
          in  withBS (Just payload) $ \payloadPtr payloadLength ->
                  withBS key $ \keyPtr keyLength ->
                      withForeignPtr t $ \ptrTopic ->
                          let realPart = if keyLength == 0 then p else UnassignedPartition
                          in  return RdKafkaMessageT
                                  { err'RdKafkaMessageT       = RdKafkaRespErrNoError
                                  , topic'RdKafkaMessageT     = ptrTopic
                                  , partition'RdKafkaMessageT = producePartitionInt realPart
                                  , len'RdKafkaMessageT       = payloadLength
                                  , payload'RdKafkaMessageT   = payloadPtr
                                  , offset'RdKafkaMessageT    = 0
                                  , keyLen'RdKafkaMessageT    = keyLength
                                  , key'RdKafkaMessageT       = keyPtr
                                  }

-- | Drains the outbound queue for a producer. This function is called automatically at the end of
-- 'runKafkaProducer' or 'runKafkaProducerConf' and usually doesn't need to be called directly.
drainOutQueue :: Kafka -> IO ()
drainOutQueue k = do
    pollEvents k 100
    l <- outboundQueueLength k
    unless (l == 0) $ drainOutQueue k
------------------------------------------------------------------------------------
keyAndPayload :: ProduceMessage -> (Maybe BS.ByteString, BS.ByteString)
keyAndPayload (ProduceMessage payload) = (Nothing, payload)
keyAndPayload (ProduceKeyedMessage key payload) = (Just key, payload)

withBS :: Maybe BS.ByteString -> (Ptr a -> Int -> IO b) -> IO b
withBS Nothing f = f nullPtr 0
withBS (Just bs) f =
    let (d, o, l) = BSI.toForeignPtr bs
    in  withForeignPtr d $ \p -> f (p `plusPtr` o) l

pollEvents :: Kafka -> Int -> IO ()
pollEvents (Kafka kPtr _) timeout = void (rdKafkaPoll kPtr timeout)

outboundQueueLength :: Kafka -> IO Int
outboundQueueLength (Kafka kPtr _) = rdKafkaOutqLen kPtr
