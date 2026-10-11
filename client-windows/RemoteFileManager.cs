using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;

namespace GameBooster
{
    public static class RemoteFileManager
    {
        private static readonly HttpClient HttpClient = new HttpClient();

        public class DriveItem
        {
            public string Name { get; set; } = string.Empty;
            public string Label { get; set; } = string.Empty;
            public double TotalGb { get; set; }
            public double FreeGb { get; set; }
            public string DriveType { get; set; } = string.Empty;
        }

        public class FileSystemEntry
        {
            public string Name { get; set; } = string.Empty;
            public string FullPath { get; set; } = string.Empty;
            public bool IsDirectory { get; set; }
            public long SizeBytes { get; set; }
            public string SizeFormatted { get; set; } = string.Empty;
            public string Extension { get; set; } = string.Empty;
            public bool IsExecutable { get; set; }
            public bool IsHidden { get; set; }
            public bool IsSystem { get; set; }
            public string LastModified { get; set; } = string.Empty;
        }

        public class DirectoryContentResult
        {
            public string CurrentPath { get; set; } = string.Empty;
            public string? ParentPath { get; set; }
            public List<FileSystemEntry> Items { get; set; } = new();
            public string? Error { get; set; }
        }

        public static List<DriveItem> GetDrives()
        {
            var list = new List<DriveItem>();
            try
            {
                foreach (var d in DriveInfo.GetDrives())
                {
                    if (!d.IsReady) continue;
                    list.Add(new DriveItem
                    {
                        Name = d.Name,
                        Label = string.IsNullOrEmpty(d.VolumeLabel) ? d.DriveType.ToString() : d.VolumeLabel,
                        TotalGb = Math.Round(d.TotalSize / (1024.0 * 1024.0 * 1024.0), 1),
                        FreeGb = Math.Round(d.AvailableFreeSpace / (1024.0 * 1024.0 * 1024.0), 1),
                        DriveType = d.DriveType.ToString()
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[FileManager] Error getting drives: {ex.Message}");
            }
            return list;
        }

        public static DirectoryContentResult ListDirectory(string? path)
        {
            var result = new DirectoryContentResult();
            try
            {
                string targetPath = path ?? "";
                if (string.IsNullOrWhiteSpace(targetPath))
                {
                    targetPath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                    if (string.IsNullOrEmpty(targetPath) || !Directory.Exists(targetPath))
                    {
                        targetPath = "C:\\";
                    }
                }

                if (!Directory.Exists(targetPath))
                {
                    result.Error = $"Directory not found: {targetPath}";
                    return result;
                }

                result.CurrentPath = Path.GetFullPath(targetPath);
                var parent = Directory.GetParent(result.CurrentPath);
                result.ParentPath = parent?.FullName;

                var dirInfo = new DirectoryInfo(result.CurrentPath);

                var enumOptions = new EnumerationOptions
                {
                    IgnoreInaccessible = true,
                    AttributesToSkip = 0, // Include hidden and system files/folders!
                    RecurseSubdirectories = false,
                    ReturnSpecialDirectories = false
                };

                // Subdirectories (including hidden ones)
                var subdirs = new List<FileSystemEntry>();
                try
                {
                    foreach (var dir in dirInfo.EnumerateDirectories("*", enumOptions))
                    {
                        try
                        {
                            bool isHidden = (dir.Attributes & FileAttributes.Hidden) != 0;
                            bool isSystem = (dir.Attributes & FileAttributes.System) != 0;

                            subdirs.Add(new FileSystemEntry
                            {
                                Name = dir.Name,
                                FullPath = dir.FullName,
                                IsDirectory = true,
                                IsHidden = isHidden,
                                IsSystem = isSystem,
                                LastModified = dir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                            });
                        }
                        catch { }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[FileManager] Warning enumerating dirs: {ex.Message}");
                }

                subdirs.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
                result.Items.AddRange(subdirs);

                // Files (including hidden ones)
                var files = new List<FileSystemEntry>();
                string[] execExtensions = { ".exe", ".msi", ".bat", ".cmd", ".ps1", ".iso", ".zip", ".rar", ".7z", ".tar", ".gz" };

                try
                {
                    foreach (var file in dirInfo.EnumerateFiles("*", enumOptions))
                    {
                        try
                        {
                            bool isHidden = (file.Attributes & FileAttributes.Hidden) != 0;
                            bool isSystem = (file.Attributes & FileAttributes.System) != 0;
                            string ext = file.Extension.ToLowerInvariant();

                            files.Add(new FileSystemEntry
                            {
                                Name = file.Name,
                                FullPath = file.FullName,
                                IsDirectory = false,
                                SizeBytes = file.Length,
                                SizeFormatted = FormatFileSize(file.Length),
                                Extension = ext,
                                IsExecutable = execExtensions.Contains(ext),
                                IsHidden = isHidden,
                                IsSystem = isSystem,
                                LastModified = file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                            });
                        }
                        catch { }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[FileManager] Warning enumerating files: {ex.Message}");
                }

                files.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
                result.Items.AddRange(files);
            }
            catch (Exception ex)
            {
                result.Error = ex.Message;
                Console.WriteLine($"[FileManager] Error in ListDirectory: {ex.Message}");
            }

            return result;
        }

        public static (bool success, string message, int? pid) ExecuteFile(string filePath, string? arguments = null)
        {
            try
            {
                if (!File.Exists(filePath))
                {
                    return (false, $"File does not exist: {filePath}", null);
                }

                var psi = new ProcessStartInfo
                {
                    FileName = filePath,
                    Arguments = arguments ?? string.Empty,
                    WorkingDirectory = Path.GetDirectoryName(filePath) ?? string.Empty,
                    UseShellExecute = true
                };

                var proc = Process.Start(psi);
                if (proc != null)
                {
                    return (true, $"Process started successfully: {Path.GetFileName(filePath)} (PID: {proc.Id})", proc.Id);
                }
                return (true, "Process started successfully.", null);
            }
            catch (Exception ex)
            {
                return (false, $"Failed to launch file: {ex.Message}", null);
            }
        }

        public static async Task<(bool success, string message)> DownloadFileAsync(
            string fileUrl, 
            string destinationFolder, 
            string? fileName = null,
            Action<int>? onProgress = null)
        {
            try
            {
                if (!Directory.Exists(destinationFolder))
                {
                    Directory.CreateDirectory(destinationFolder);
                }

                string targetFileName = fileName ?? Path.GetFileName(new Uri(fileUrl).LocalPath);
                if (string.IsNullOrWhiteSpace(targetFileName))
                {
                    targetFileName = $"download_{DateTime.Now:yyyyMMdd_HHmmss}.bin";
                }

                string destinationPath = Path.Combine(destinationFolder, targetFileName);

                using var response = await HttpClient.GetAsync(fileUrl, HttpCompletionOption.ResponseHeadersRead);
                response.EnsureSuccessStatusCode();

                long? totalBytes = response.Content.Headers.ContentLength;

                using var contentStream = await response.Content.ReadAsStreamAsync();
                using var fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

                var buffer = new byte[16384];
                long totalRead = 0;
                int bytesRead;

                while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, bytesRead);
                    totalRead += bytesRead;

                    if (totalBytes.HasValue && totalBytes.Value > 0 && onProgress != null)
                    {
                        int progress = (int)((totalRead * 100) / totalBytes.Value);
                        onProgress(progress);
                    }
                }

                return (true, $"Successfully downloaded {targetFileName} to {destinationFolder} ({FormatFileSize(totalRead)})");
            }
            catch (Exception ex)
            {
                return (false, $"Download error: {ex.Message}");
            }
        }

        public static string FormatFileSize(long bytes)
        {
            if (bytes < 1024) return $"{bytes} B";
            if (bytes < 1024 * 1024) return $"{Math.Round(bytes / 1024.0, 1)} KB";
            if (bytes < 1024 * 1024 * 1024) return $"{Math.Round(bytes / (1024.0 * 1024.0), 1)} MB";
            return $"{Math.Round(bytes / (1024.0 * 1024.0 * 1024.0), 2)} GB";
        }

        public static (bool success, string message, string? path) CreateFolder(string parentPath, string folderName)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(folderName)) return (false, "Folder name is empty", null);
                string newPath = Path.Combine(parentPath, folderName);
                if (Directory.Exists(newPath)) return (false, "Folder already exists", newPath);
                Directory.CreateDirectory(newPath);
                return (true, $"Folder created: {folderName}", newPath);
            }
            catch (Exception ex)
            {
                return (false, $"Failed to create folder: {ex.Message}", null);
            }
        }

        public static (bool success, string message) DeleteItem(string targetPath)
        {
            try
            {
                if (File.Exists(targetPath))
                {
                    File.Delete(targetPath);
                    return (true, $"File deleted: {Path.GetFileName(targetPath)}");
                }
                if (Directory.Exists(targetPath))
                {
                    Directory.Delete(targetPath, true);
                    return (true, $"Folder deleted: {Path.GetFileName(targetPath)}");
                }
                return (false, "Item not found");
            }
            catch (Exception ex)
            {
                return (false, $"Failed to delete: {ex.Message}");
            }
        }
    }
}
