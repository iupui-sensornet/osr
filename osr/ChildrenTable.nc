/*
 * Interface to manipulate the children table
 */
 
interface ChildrenTable {
	/*
	 * Add the child id into the table
	 */
	command void update(uint16_t child_id);
	
	
	/*
	 * Decrease TTL on all the children 
	 */
	command void decreaseTtl();
	
}
