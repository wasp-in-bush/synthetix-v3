import { task } from 'hardhat/config';
import { SUBTASK_STORAGE_LOAD_DUMP, TASK_STORAGE_VERIFY } from '../task-names';

import type { SourceUnit } from '@solidity-parser/parser/src/ast-types';

interface Params {
  previous: string;
  current: string;
}

task(
  TASK_STORAGE_VERIFY,
  'Using the two given storage dumps, verify that there are not invalid storage mutations'
)
  .addOptionalPositionalParam(
    'previous',
    'Older storage dump to compare to',
    'storage.dump.prev.sol'
  )
  .addOptionalPositionalParam(
    'current',
    'More recent storage dump to compare to',
    'storage.dump.sol'
  )
  .setAction(async (params: Required<Params>, hre) => {
    const currSourceUnits: SourceUnit[] = await hre.run(SUBTASK_STORAGE_LOAD_DUMP, {
      filepath: params.current,
    });

    console.log(JSON.stringify(currSourceUnits, null, 2));
  });
