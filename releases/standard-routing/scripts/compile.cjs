
const fs = require("node:fs");
const crypto = require("node:crypto");
const solc = require("solc");
const manifest = JSON.parse(fs.readFileSync("manifest.json", "utf8"));
const digest = value => crypto.createHash("sha256").update(value).digest("hex");
fs.mkdirSync("build", { recursive: true });
const outputs = new Map();
for (const compiler of manifest.compilerInputs) {
  if (!solc.version().startsWith(compiler.solcLongVersion)) throw Error("Wrong compiler version");
  const text = fs.readFileSync(compiler.file, "utf8");
  if (digest(text) !== compiler.sha256) throw Error("Compiler input changed");
  const targets = manifest.contracts.filter(contract => contract.compilerInput === compiler.file);
  const input = JSON.parse(text);
  // Output selection does not affect Solidity metadata or code generation for
  // a selected contract. Keep the original files intact and every source and
  // bytecode-affecting setting unchanged; compare exact bytecode afterward.
  input.settings.outputSelection = {};
  for (const contract of targets) {
    input.settings.outputSelection[contract.sourceName] ||= {};
    input.settings.outputSelection[contract.sourceName][contract.name] =
      ["abi", "evm.bytecode", "evm.deployedBytecode", "storageLayout"];
  }
  console.log("Rebuilding: " + targets.map(contract => contract.name).join(", "));
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const failures = (output.errors || []).filter(error => error.severity === "error");
  if (failures.length) throw Error(failures.map(error => error.formattedMessage).join("\n"));
  outputs.set(compiler.file, output);
}
for (const contract of manifest.contracts) {
  const artifact = JSON.parse(fs.readFileSync(contract.artifact, "utf8"));
  const rebuilt = outputs.get(contract.compilerInput).contracts[contract.sourceName][contract.name];
  if ("0x" + rebuilt.evm.bytecode.object !== artifact.bytecode ||
      "0x" + rebuilt.evm.deployedBytecode.object !== artifact.deployedBytecode)
    throw Error("Reproducibility failure: " + contract.name);
  fs.writeFileSync("build/" + contract.name + ".json", JSON.stringify(rebuilt, null, 2));
  console.log("Exact creation/runtime template match: " + contract.name);
}
