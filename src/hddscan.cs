using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace hdd_scan
{
    class Program
    {
        static string[] smartctl(string arg)
        {
            Process p = new Process();
            p.StartInfo.FileName = "C:\\Program Files\\Zabbix\\extra\\smart\\smartctl.exe";
            p.StartInfo.Arguments = arg;
            p.StartInfo.UseShellExecute = false;
            p.StartInfo.RedirectStandardOutput = true;
            p.Start();
            string output = p.StandardOutput.ReadToEnd();
            string[] list = output.Split('\n');
            p.WaitForExit();
            return list;
        }

        static void Main(string[] args)
        {
            try
            {

                string[] hddlist = smartctl("--scan");
                Dictionary<string, string> psarr = new Dictionary<string, string>();
                string pattern = @"^(?<1>\/[\w]+)\/(?<xer>[\S]+)\s";
                foreach (string hdd in hddlist)
                {
                    var match = Regex.Match(hdd, pattern);
                    if (match.Success)
                    {
                        string shdd = match.Groups["xer"].Value;
                        string[] tmp = smartctl("-a " + shdd);
                        foreach (string line in tmp)
                        {
                            if (line.Contains("Serial") == true)
                            {
                                string[] serials = Regex.Split(line, @"^Serial\sNumber\:\s+");
                                if (serials.Length < 2) continue;
                                string serial = serials[1];

                                if (!psarr.ContainsValue(serial))
                                {
                                    psarr.Add(shdd, serial);
                                }
                            }
                        }
                    }
                }

                //Starting output
                int cnt = 0;
                Console.WriteLine("{\n");
                Console.WriteLine("\t\"data\":[\n\n");
                foreach (KeyValuePair<string, string> kvp in psarr)
                {
                    string[] flist = smartctl("-a "+kvp.Key);
                    string checkstring = "A mandatory SMART command failed: exiting. To continue, add one or more '-T permissive' options.";
                   
                    //
                    bool test= false;
                    for (int i = 0; i < flist.Length; i++)
                    {
                        if (flist[i].Contains(checkstring))
                        {
                            test = true;
                        }
                    }
                    if (!test)
                    {
                        cnt++;
                        if (cnt > 1)
                        {
                            Console.WriteLine("\t,\n");
                        }
                        Console.WriteLine("\t{\n");
                        Console.WriteLine("\t\t\"{{#HDDNAME}}\":\"{0}\"\n", kvp.Key);
                        Console.WriteLine("\t}\n");
                    }
                }

                Console.WriteLine("\n\t]\n");
                Console.WriteLine("}\n");

            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.Message);
}
        }
    }
}

