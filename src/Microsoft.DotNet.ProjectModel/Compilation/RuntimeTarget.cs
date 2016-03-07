using System.Linq;
using System.Collections.Generic;

namespace Microsoft.DotNet.ProjectModel.Compilation
{
    public class RuntimeTarget
    {
        public RuntimeTarget(string runtime,
            IEnumerable<LibraryAsset> runtimeAssemblies,
            IEnumerable<LibraryAsset> nativeLibraries)
        {
            Runtime = runtime;
            RuntimeAssemblies = runtimeAssemblies.ToArray();
            NativeLibraries = nativeLibraries.ToArray();
        }

        public string Runtime { get; }

        /// <summary>
        /// Gets a list of fully-qualified paths to MSIL binaries required to run
        /// </summary>
        public IReadOnlyList<LibraryAsset> RuntimeAssemblies { get; }

        /// <summary>
        /// Gets a list of fully-qualified paths to native binaries required to run
        /// </summary>
        public IReadOnlyList<LibraryAsset> NativeLibraries { get; }
    }
}