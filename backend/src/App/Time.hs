module App.Time (appToday, appDayAt) where
import Data.Time

-- Business dates use Sao Paulo (UTC-03); never the host/browser timezone.
appDayAt :: UTCTime -> Day
appDayAt = localDay . utcToLocalTime (minutesToTimeZone (-180))
appToday :: IO Day
appToday = appDayAt <$> getCurrentTime
