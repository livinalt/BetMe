import { cre, Runner, type Runtime } from "@chainlink/cre-sdk";
import { onHttpTrigger } from "./httpCallback";
import { onLogTrigger } from "./logCallback";

type Config = {
  geminiModel: string;
  evms: Array<{
    marketAddress: string;
    chainSelectorName: string;
    gasLimit: string;
  }>;
};

const initWorkflow = (config: Config) => {
  const httpCapability = new cre.capabilities.HTTPCapability();
  const httpTrigger = httpCapability.trigger({});

  const evmClient = new cre.capabilities.EVMClient();
  const evmLogTrigger = evmClient.trigger({
    chainSelectorName: config.evms[0].chainSelectorName,
    isTestnet: true,
    address: config.evms[0].marketAddress,
    eventSignature: "SettlementRequested(uint256,string)",
  });

  return [
    cre.handler(httpTrigger, onHttpTrigger),
    cre.handler(evmLogTrigger, onLogTrigger),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();