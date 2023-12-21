using System;
using System.Collections.Generic;
using System.Data.SqlTypes;
using System.IO;
using System.Reflection.PortableExecutable;
using System.Text;
using Sys = Cosmos.System;

namespace NewOS
{
    public class Kernel: Sys.Kernel
    {
        Sys.FileSystem.CosmosVFS fs;
        string currentDirectory = @"0:\";
        protected override void BeforeRun()
        {
            fs = new Sys.FileSystem.CosmosVFS();
            Sys.FileSystem.VFS.VFSManager.RegisterVFS(fs);
            ClearConsole();
            Console.ForegroundColor = ConsoleColor.White;
            Console.WriteLine("Welcome to NewOS!");
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("0.1 Alpha Console");
        }
        
        protected override void Run()
        {
            Console.ForegroundColor = ConsoleColor.White;
            Console.Write("OS >> ");
            Commands();
        }
        public void Commands()
        {
            string filename = "";
            string dirname = "";
            string text = "";

            var input = Console.ReadLine();
            switch (input)
            {
                default:
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine(input + ": Unknown Command");
                    break;
                case "help":
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("==================Help==================");
                    Console.WriteLine("shutdown - Power off computer");
                    Console.WriteLine("reboot - Reboot computer");
                    Console.WriteLine("ls - Snow all files in current directory");
                    Console.WriteLine("cd - Move to directory");
                    Console.WriteLine("fs - File system type");
                    Console.WriteLine("space - Get aviliable space");
                    Console.WriteLine("datetime - Current date and time");
                    Console.WriteLine("========================================");
                    break;
                case "shutdown":
                    ClearConsole();
                    System.Threading.Thread.Sleep(300);
                    Cosmos.System.Power.Shutdown();
                    break;
                case "reboot":
                    Cosmos.System.Power.Reboot();
                    break;
                case "sysinfo":
                    string CPUBrand = Cosmos.Core.CPU.GetCPUBrandString();
                    string CPUVendor = Cosmos.Core.CPU.GetCPUVendorName();
                    uint AllRAM = Cosmos.Core.CPU.GetAmountOfRAM();
                    ulong AviliableRAM = Cosmos.Core.GCImplementation.GetAvailableRAM();
                    uint UsedRAM = Cosmos.Core.GCImplementation.GetUsedRAM();
                    Console.WriteLine(@"CPU: {0}
CPU Vendor: {1}
Amount of RAM: {2}
Used RAM: {3}", CPUBrand, CPUVendor, AllRAM, UsedRAM);
                    break;
                case "clear":
                    ClearConsole();
                    break;
                case "makefile":
                    filename = Console.ReadLine();
                    fs.CreateFile(currentDirectory + filename);
                    break;
                case "mkdir":
                    dirname = Console.ReadLine();
                    fs.CreateDirectory(currentDirectory + dirname);
                    break;
                case "del":
                    filename = Console.ReadLine();
                    Sys.FileSystem.VFS.VFSManager.DeleteFile(currentDirectory + filename);
                    break;
                case "deldir":
                    dirname = Console.ReadLine();
                    Sys.FileSystem.VFS.VFSManager.DeleteDirectory(currentDirectory + dirname, true);
                    break;
                case "ls":
                    try
                    {
                        var directory_list = Sys.FileSystem.VFS.VFSManager.GetDirectoryListing(currentDirectory);
                        foreach (var directoryEntry in directory_list)
                        {
                            try
                            {
                                var entry_type = directoryEntry.mEntryType;
                                if (entry_type == Sys.FileSystem.Listing.DirectoryEntryTypeEnum.File)
                                {
                                    Console.ForegroundColor = ConsoleColor.Magenta;
                                    Console.WriteLine("| <FILE>       " + directoryEntry.mName);
                                    Console.ForegroundColor = ConsoleColor.White;
                                }
                                if (entry_type == Sys.FileSystem.Listing.DirectoryEntryTypeEnum.Directory)
                                {
                                    Console.ForegroundColor = ConsoleColor.Blue;
                                    Console.WriteLine("| <DIR>      " + directoryEntry.mName);
                                    Console.ForegroundColor = ConsoleColor.White;
                                }
                            }
                            catch (Exception e)
                            {
                                Console.WriteLine("Error: Directory not found");
                                Console.WriteLine(e.ToString());
                            }

                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine(ex.ToString());
                        break;
                    }
                    break;
                case "cd":
                    currentDirectory = Console.ReadLine();
                    break;
                case "space":
                    var available_space = fs.GetAvailableFreeSpace(@"0:\");
                    Console.WriteLine("Available Space: " + available_space);
                    break;
                case "fs":
                    var fs_type = fs.GetFileSystemType(@"0:\");
                    Console.WriteLine("File System Type: " + fs_type);
                    break;
                case "datetime":
                    Console.WriteLine(DateTime.Now);
                    break;
                case "read":
                    filename = Console.ReadLine();
                    try
                    {
                        Console.WriteLine(File.ReadAllText(@"0:\" + filename));
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine(e.ToString());
                    }
                    break;
                case "readbytes":
                    filename = Console.ReadLine();
                    try
                    {
                        Console.WriteLine(File.ReadAllBytes(@"0:\" + filename));
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine(e.ToString());
                    }
                    break;
                case "write":
                    filename = Console.ReadLine();
                    text = Console.ReadLine();
                    try
                    {
                        File.AppendAllText(@"0:\" + filename, Environment.NewLine + text);
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine(e.ToString());
                    }
                    break;

            }
        }

        public void ClearConsole()
        {
            Console.Clear();
            Console.BackgroundColor = ConsoleColor.Blue;
            Console.WriteLine("NewOS                                                  " + DateTime.Now);
            Console.ForegroundColor = ConsoleColor.White;
            Console.BackgroundColor = ConsoleColor.Black;
        }
    }
}
