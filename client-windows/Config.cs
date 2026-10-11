using System;
using System.IO;
using System.Text.Json;

namespace GameRoomAgent
{
    public class Config
    {
        public string ServerUrl { get; set; } = "ws://192.168.1.100:3000/ws/client";
        public string StationId { get; set; } = "laptop-01";
        public string StationName { get; set; } = "Gaming Laptop 01";
        public string AuthToken { get; set; } = "gameroom_secret_key_2026";
        public bool AutoStartWithWindows { get; set; } = true;
        public int TelemetryIntervalSeconds { get; set; } = 3;
        public bool AutoLockOnDisconnect { get; set; } = false;

        public static Config Load()
        {
            try
            {
                string configPath = Path.Combine(AppContext.BaseDirectory, "config.json");
                if (File.Exists(configPath))
                {
                    string json = File.ReadAllText(configPath);
                    var loaded = JsonSerializer.Deserialize<Config>(json, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });
                    if (loaded != null)
                    {
                        return loaded;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error loading config: {ex.Message}. Using defaults.");
            }

            return new Config();
        }
    }
}
