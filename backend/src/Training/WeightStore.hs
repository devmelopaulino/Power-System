{-# LANGUAGE OverloadedStrings #-}
module Training.WeightStore (writeWeight, rebuildDay) where
import Control.Monad (void)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (Day)
import Database.PostgreSQL.Simple

-- Caller supplies a transaction. Serialize onboarding, check-ins and corrections.
writeWeight :: Connection -> Int64 -> Day -> Double -> Text -> IO ()
writeWeight connection studentId day weight source = do
 void (query connection "SELECT id FROM alunos WHERE id=? FOR UPDATE" (Only studentId) :: IO [Only Int64])
 void $ execute connection "INSERT INTO historico_pesagens(aluno_id,data,peso,origem) VALUES (?,?,?,?)" (studentId,day,weight,source)
 rebuildDay connection studentId day

rebuildDay :: Connection -> Int64 -> Day -> IO ()
rebuildDay connection studentId day = do
 void $ execute connection "DELETE FROM pesos_alunos WHERE aluno_id=? AND data=?" (studentId,day)
 void $ execute connection "INSERT INTO pesos_alunos(aluno_id,data,peso,origem,atualizado_em) SELECT aluno_id,data,peso,origem,registrado_em FROM historico_pesagens WHERE aluno_id=? AND data=? AND excluido_em IS NULL ORDER BY registrado_em DESC,id DESC LIMIT 1" (studentId,day)
